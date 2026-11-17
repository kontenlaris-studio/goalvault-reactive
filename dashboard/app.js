/* GoalVault dashboard — plain static JS + ethers v6 (CDN). No build step.
 * Reads are done over a public Sepolia RPC (no wallet needed); writes go
 * through the visitor's own wallet (MetaMask etc.) on Sepolia. */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);

  // --- Graceful degradation ---------------------------------------------------
  // If config.js failed to load or the ethers CDN is unreachable, the page must
  // still render an explanation instead of dying mid-script with a blank
  // "Loading vault state…" (the pre-audit behaviour when `ethers` was missing:
  // the whole IIFE threw at the JsonRpcProvider line).
  if (!window.GOALVAULT_CONFIG || typeof window.ethers === "undefined") {
    const banner = $("previewBanner");
    if (banner) {
      banner.classList.remove("hidden");
      banner.innerHTML = "<strong>Dashboard unavailable:</strong> a required script (config.js or the ethers library) did not load. Check your connection and reload — no funds are involved, this page is read-only until you connect a wallet.";
    }
    const box = $("myAutomations");
    if (box) box.innerHTML = '<p class="empty">Not loaded — see the notice above.</p>';
    return;
  }
  const CFG = window.GOALVAULT_CONFIG;

  const escapeHtml = (s) =>
    String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // --- Template definitions: the low-code layer ------------------------------
  // Adding a template = one entry here + one registry row on-chain.
  const TEMPLATES = {
    goalvault: {
      title: "Savings Goal",
      contractKey: "goalVault",
      reactiveKey: "goalReactiveGoalVault",
      callbackKey: "goalCallbackGoalVault",
      createFn: "createGoal",
      cancelFn: "cancelGoal",
      countFn: "goalCount",
      getFn: "getGoal",
      stateFn: "getGoalState",
      createdEvent: "GoalCreated",
      beneficiaryLabel: "Who should receive the money when the target is reached?",
      targetLabel: "How much are you saving toward the target?",
      partyWord: "Beneficiary",
    },
    escrow: {
      title: "Pay When Funded",
      contractKey: "escrowVault",
      reactiveKey: "goalReactiveEscrowVault",
      callbackKey: "goalCallbackEscrowVault",
      createFn: "createEscrow",
      cancelFn: "cancelEscrow",
      countFn: "escrowCount",
      getFn: "getEscrow",
      stateFn: "getEscrowState",
      createdEvent: "EscrowCreated",
      beneficiaryLabel: "Who did the work / who should be paid?",
      targetLabel: "What is the agreed price?",
      partyWord: "Freelancer",
    },
  };

  const VAULT_ABI = [
    "function createGoal(address beneficiary, uint256 target) returns (uint256)",
    "function createEscrow(address freelancer, uint256 target) returns (uint256)",
    "function cancelGoal(uint256 id)",
    "function cancelEscrow(uint256 id)",
    "function deposit(uint256 id) payable",
    "function withdraw()",
    "function pendingWithdrawals(address account) view returns (uint256)",
    "function goalCount() view returns (uint256)",
    "function escrowCount() view returns (uint256)",
    "function getGoal(uint256 id) view returns (address, address, uint256, uint256, bool)",
    "function getEscrow(uint256 id) view returns (address, address, uint256, uint256, bool)",
    "function getGoalState(uint256 id) view returns (bool, bool)",
    "function getEscrowState(uint256 id) view returns (bool, bool)",
    "event GoalCreated(uint256 indexed goalId, address indexed owner, address indexed beneficiary, uint256 target)",
    "event EscrowCreated(uint256 indexed escrowId, address indexed client, address indexed freelancer, uint256 target)",
  ];
  const REACTIVE_ABI = ["function paused() view returns (bool)"];

  let selectedTemplate = "goalvault";
  let signer = null;
  let signerAddress = null;
  const readProvider = new ethers.JsonRpcProvider(CFG.sepolia.rpc);
  const lasnaProvider = new ethers.JsonRpcProvider(CFG.lasna.rpc);

  const deployed = (key) => {
    const a = CFG.contracts[key];
    return a && ethers.isAddress(a) && a !== ethers.ZeroAddress;
  };
  const anyDeployed = () => deployed("goalVault") || deployed("escrowVault");

  // --- Local labels (names live only in this browser) ------------------------
  const store = {
    load() { try { return JSON.parse(localStorage.getItem("goalvault.mine") || "[]"); } catch { return []; } },
    save(list) { localStorage.setItem("goalvault.mine", JSON.stringify(list)); },
    add(entry) { const l = store.load(); l.push(entry); store.save(l); },
    nameFor(template, id) {
      const hit = store.load().find((e) => e.template === template && e.id === id);
      return hit ? hit.name : "";
    },
  };

  // --- Form -> deployment parameters -----------------------------------------
  function formValues() {
    const ben = $("fBeneficiary").value.trim();
    const targetEth = $("fTarget").value.trim();
    let targetWei = null;
    try { if (targetEth) targetWei = ethers.parseEther(targetEth); } catch { /* invalid */ }
    return { name: $("fName").value.trim(), beneficiary: ben, targetEth, targetWei };
  }

  function renderParams() {
    const t = TEMPLATES[selectedTemplate];
    const v = formValues();
    const params = {
      template: t.title,
      originChain: `${CFG.sepolia.name} (${CFG.sepolia.chainId})`,
      vaultContract: deployed(t.contractKey) ? CFG.contracts[t.contractKey] : "<filled in after deployment>",
      functionCall: `${t.createFn}(beneficiary, target)`,
      arguments: {
        beneficiary: v.beneficiary || "<wallet address from the form>",
        target: v.targetWei !== null ? `${v.targetWei.toString()} wei (${v.targetEth} ETH)` : "<amount from the form>",
        depositToken: "native ETH (no token approval needed)",
      },
      watchedEvent: "Deposited(goalId, depositor, amount, total, target)",
      reactiveContract: deployed(t.reactiveKey) ? CFG.contracts[t.reactiveKey] : "<filled in after deployment>",
      reactiveNetwork: `${CFG.lasna.name} (${CFG.lasna.chainId})`,
      callbackContract: deployed(t.callbackKey) ? CFG.contracts[t.callbackKey] : "<filled in after deployment>",
      callbackCall: "onGoalReached(reactive, goalId) → vault.release(goalId)",
      whatHappensNext: "Fund it in any number of deposits. The deposit that reaches the target triggers the payout automatically.",
    };
    $("paramPreview").textContent = JSON.stringify(params, null, 2);
    // Disable per SELECTED template (pre-audit this used anyDeployed(), so the
    // button lit up when only the *other* template was deployed).
    $("createBtn").disabled = !deployed(t.contractKey);
  }

  // --- Wallet -----------------------------------------------------------------
  async function ensureSepolia() {
    const want = "0x" + CFG.sepolia.chainId.toString(16);
    try {
      await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: want }] });
    } catch (e) {
      if (e && e.code === 4902) {
        // Chain unknown to the wallet — add Sepolia instead of dead-ending.
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: want,
            chainName: CFG.sepolia.name,
            rpcUrls: [CFG.sepolia.rpc],
            blockExplorerUrls: [CFG.sepolia.explorer],
            nativeCurrency: { name: "Sepolia Ether", symbol: "ETH", decimals: 18 },
          }],
        });
      } else {
        throw e;
      }
    }
    const provider = new ethers.BrowserProvider(window.ethereum);
    const net = await provider.getNetwork();
    return Number(net.chainId) === CFG.sepolia.chainId;
  }

  async function connectWallet() {
    if (!window.ethereum) {
      $("walletInfo").textContent = "No wallet found in this browser — install MetaMask to create automations. Browsing still works.";
      return;
    }
    try {
      const provider = new ethers.BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      if (Number((await provider.getNetwork()).chainId) !== CFG.sepolia.chainId) {
        if (!(await ensureSepolia())) {
          $("walletInfo").textContent = "Please switch your wallet to Ethereum Sepolia to create automations.";
          return;
        }
      }
      signer = await provider.getSigner();
      signerAddress = await signer.getAddress();
      $("walletInfo").textContent = `Connected: ${signerAddress} · ${CFG.sepolia.name}`;
      $("connectBtn").textContent = "Wallet connected ✓";
      await refreshAutomations();
      await refreshRefunds();
    } catch (e) {
      // Includes the user rejecting the connection request (pre-audit this was
      // an unhandled rejection and the UI silently did nothing).
      $("walletInfo").textContent = "Wallet connection failed or was rejected: " + (e.shortMessage || e.message || e);
    }
  }

  // --- Create -------------------------------------------------------------------
  async function createAutomation() {
    const t = TEMPLATES[selectedTemplate];
    const v = formValues();
    const status = $("createStatus");
    if (!deployed(t.contractKey)) { status.textContent = "This template is not deployed yet (preview mode)."; return; }
    if (!signer) { status.textContent = "Connect your wallet first."; return; }
    if (!ethers.isAddress(v.beneficiary)) { status.textContent = "That beneficiary address doesn't look right."; return; }
    if (v.targetWei === null || v.targetWei <= 0n) { status.textContent = "Enter a target amount above 0."; return; }
    try {
      status.textContent = "Sending transaction — confirm it in your wallet…";
      const contract = new ethers.Contract(CFG.contracts[t.contractKey], VAULT_ABI, signer);
      const tx = await contract[t.createFn](v.beneficiary, v.targetWei);
      const receipt = await tx.wait();
      let newId = null;
      for (const log of receipt.logs) {
        try {
          const parsed = contract.interface.parseLog(log);
          if (parsed && parsed.name === t.createdEvent) { newId = Number(parsed.args[0]); break; }
        } catch { /* not our event */ }
      }
      if (newId === null) newId = Number(await contract[t.countFn]()) - 1;
      store.add({ template: selectedTemplate, id: newId, name: v.name || t.title });
      status.innerHTML = `Created automation #${newId}! Tx: <a target="_blank" href="${CFG.sepolia.explorer}/tx/${receipt.hash}">${receipt.hash.slice(0, 14)}…</a> Now top it up below — the payout triggers itself at 100%.`;
      await refreshAutomations();
    } catch (e) {
      status.textContent = "Transaction failed or was rejected: " + (e.shortMessage || e.message || e);
    }
  }

  // --- My automations (live reads) ----------------------------------------------
  async function fetchAutomations() {
    const out = [];
    for (const [key, t] of Object.entries(TEMPLATES)) {
      if (!deployed(t.contractKey)) continue;
      const contract = new ethers.Contract(CFG.contracts[t.contractKey], VAULT_ABI, readProvider);
      const count = Number(await contract[t.countFn]());
      const mine = new Set(store.load().filter((e) => e.template === key).map((e) => e.id));
      // Demo-scale vaults: list everything while the count is small, plus anything of mine.
      const ids = new Set(mine);
      if (count <= 25) for (let i = 0; i < count; i++) ids.add(i);
      for (const id of [...ids].sort((a, b) => a - b)) {
        const [ownerAddr, party, target, total, done] = await contract[t.getFn](id);
        const [, cancelled] = await contract[t.stateFn](id);
        out.push({ template: key, t, id, ownerAddr, party, target, total, done, cancelled });
      }
    }
    return out;
  }

  function renderAutomations(list) {
    const box = $("myAutomations");
    const sel = $("dSelect");
    sel.innerHTML = "";
    if (!anyDeployed()) {
      box.innerHTML = `<p class="empty">Preview mode: once the contracts are deployed (addresses in <code>config.js</code>), every automation will appear here with live progress — read straight from Sepolia, no server involved.</p>`;
      return;
    }
    if (!list.length) {
      box.innerHTML = `<p class="empty">No automations yet. Create your first one above — it takes one form and one click.</p>`;
      return;
    }
    box.innerHTML = "";
    for (const a of list) {
      const pct = a.target > 0n ? Math.min(100, Number((a.total * 10000n) / a.target) / 100) : 0;
      // Names come from localStorage (user-typed) — always escape before innerHTML.
      const name = escapeHtml(store.nameFor(a.template, a.id) || `${a.t.title} #${a.id}`);
      const status = a.cancelled
        ? '<span class="badge cancelled">✕ Cancelled — refunds credited</span>'
        : a.done
          ? '<span class="badge">✓ Completed — paid out automatically</span>'
          : '<span class="badge waiting">● Watching… set & forget</span>';
      const mine = signerAddress && a.ownerAddr.toLowerCase() === signerAddress.toLowerCase();
      const cancelBtn = mine && !a.done && !a.cancelled
        ? `<button class="btn danger" data-cancel="${a.template}:${a.id}">Cancel & refund contributors</button>`
        : "";
      const card = document.createElement("div");
      card.className = "auto";
      card.innerHTML = `
        <div class="top"><h3>${name}</h3>${status}</div>
        <div class="bar"><div style="width:${pct}%"></div></div>
        <div class="meta">
          <span><strong>${ethers.formatEther(a.total)} / ${ethers.formatEther(a.target)} ETH</strong> (${pct}%)</span>
          <span>${a.t.partyWord}: <a target="_blank" href="${CFG.sepolia.explorer}/address/${a.party}">${a.party.slice(0, 10)}…</a></span>
          <span>Template: ${a.t.title}</span>
          <span><a target="_blank" href="${CFG.sepolia.explorer}/address/${CFG.contracts[a.t.contractKey]}">Vault on Etherscan ↗</a></span>
          ${cancelBtn}
        </div>
        <span class="status" data-cancel-status="${a.template}:${a.id}"></span>`;
      box.appendChild(card);
      const opt = document.createElement("option");
      opt.value = `${a.template}:${a.id}`;
      opt.textContent = `${name} — ${ethers.formatEther(a.total)}/${ethers.formatEther(a.target)} ETH`;
      if (!a.done && !a.cancelled) sel.appendChild(opt);
    }
  }

  // --- Cancel & refunds (creator tools) -----------------------------------------
  async function cancelAutomation(templateKey, id, statusEl) {
    const t = TEMPLATES[templateKey];
    if (!signer) { statusEl.textContent = "Connect the creator wallet first."; return; }
    try {
      statusEl.textContent = "Sending cancel — confirm in your wallet…";
      const contract = new ethers.Contract(CFG.contracts[t.contractKey], VAULT_ABI, signer);
      const tx = await contract[t.cancelFn](id);
      await tx.wait();
      statusEl.textContent = "Cancelled. Every contributor's refund is credited — claim it with Withdraw below.";
      await refreshAutomations();
      await refreshRefunds();
    } catch (e) {
      statusEl.textContent = "Cancel failed or was rejected: " + (e.shortMessage || e.message || e);
    }
  }

  async function refreshRefunds() {
    const bar = $("refundBar");
    if (!bar) return;
    if (!signer || !anyDeployed()) { bar.classList.add("hidden"); return; }
    let html = "";
    for (const t of Object.values(TEMPLATES)) {
      if (!deployed(t.contractKey)) continue;
      try {
        const contract = new ethers.Contract(CFG.contracts[t.contractKey], VAULT_ABI, readProvider);
        const amt = await contract.pendingWithdrawals(signerAddress);
        if (amt > 0n) {
          html += `<div class="row actions"><span><strong>${ethers.formatEther(amt)} ETH</strong> waiting for you in ${t.title} (deferred payout or refund).</span><button class="btn" data-withdraw="${t.contractKey}">Withdraw</button></div>`;
        }
      } catch { /* RPC hiccup — leave the bar as-is */ }
    }
    bar.innerHTML = html;
    bar.classList.toggle("hidden", !html);
  }

  async function withdrawRefund(contractKey, btn) {
    const t = Object.values(TEMPLATES).find((x) => x.contractKey === contractKey);
    try {
      btn.disabled = true;
      const contract = new ethers.Contract(CFG.contracts[t.contractKey], VAULT_ABI, signer);
      const tx = await contract.withdraw();
      await tx.wait();
      await refreshRefunds();
    } catch (e) {
      btn.disabled = false;
      btn.textContent = "Withdraw failed — retry";
    }
  }

  async function refreshAutomations() {
    try { renderAutomations(await fetchAutomations()); }
    catch (e) { $("myAutomations").innerHTML = `<p class="empty">Could not read vault state from the Sepolia RPC right now (${e.shortMessage || e.message}). Try Refresh.</p>`; }
  }

  // --- Deposit --------------------------------------------------------------------
  async function deposit(ev) {
    ev.preventDefault();
    const status = $("depositStatus");
    const [templateKey, idStr] = ($("dSelect").value || "").split(":");
    const amount = $("dAmount").value.trim();
    if (!templateKey) { status.textContent = "No open automation to top up."; return; }
    if (!signer) { status.textContent = "Connect your wallet first."; return; }
    let wei;
    try { wei = ethers.parseEther(amount); } catch { status.textContent = "Enter a valid amount."; return; }
    const t = TEMPLATES[templateKey];
    try {
      status.textContent = "Sending deposit — confirm in your wallet…";
      const contract = new ethers.Contract(CFG.contracts[t.contractKey], VAULT_ABI, signer);
      const tx = await contract.deposit(Number(idStr), { value: wei });
      const receipt = await tx.wait();
      status.innerHTML = `Deposit landed: <a target="_blank" href="${CFG.sepolia.explorer}/tx/${receipt.hash}">${receipt.hash.slice(0, 14)}…</a> If that crossed the target, Reactive is already releasing the payout — refresh in a few seconds.`;
      await refreshAutomations();
    } catch (e) {
      status.textContent = "Deposit failed or was rejected: " + (e.shortMessage || e.message || e);
    }
  }

  // --- Reactive status panel -------------------------------------------------------
  async function renderReactiveStatus() {
    const el = $("reactiveStatus");
    if (!el) return;
    const rows = [];
    try {
      const net = await lasnaProvider.getNetwork();
      const ok = Number(net.chainId) === CFG.lasna.chainId;
      rows.push(`<li>Lasna network: ${ok ? "✓ reachable" : "⚠ unexpected chain"} — chain id <code>${Number(net.chainId)}</code> (expected ${CFG.lasna.chainId})</li>`);
    } catch {
      rows.push(`<li>Lasna network: ⚠ RPC not reachable right now (${CFG.lasna.rpc})</li>`);
    }
    rows.push(`<li>System contract: <a target="_blank" href="${CFG.lasna.explorer}/address/${CFG.systemContract}"><code>${CFG.systemContract}</code></a> on Lasna</li>`);
    rows.push(`<li>Sepolia callback proxy: <a target="_blank" href="${CFG.sepolia.explorer}/address/${CFG.sepoliaCallbackProxy}"><code>${CFG.sepoliaCallbackProxy}</code></a></li>`);
    if (deployed("templateRegistry")) {
      rows.push(`<li>Template registry: <a target="_blank" href="${CFG.sepolia.explorer}/address/${CFG.contracts.templateRegistry}"><code>${CFG.contracts.templateRegistry}</code></a></li>`);
    }
    for (const t of Object.values(TEMPLATES)) {
      if (!deployed(t.contractKey)) {
        rows.push(`<li>${t.title}: not deployed yet (preview mode)</li>`);
        continue;
      }
      let pausedTxt = "status unknown";
      if (deployed(t.reactiveKey)) {
        try {
          const rc = new ethers.Contract(CFG.contracts[t.reactiveKey], REACTIVE_ABI, lasnaProvider);
          pausedTxt = (await rc.paused()) ? "⏸ paused by owner (unsubscribed)" : "▶ live (subscribed)";
        } catch { /* reactive read failed — keep generic text */ }
      }
      rows.push(`<li>${t.title}: reactive <a target="_blank" href="${CFG.lasna.explorer}/address/${CFG.contracts[t.reactiveKey]}"><code>${CFG.contracts[t.reactiveKey].slice(0, 10)}…</code></a> ${pausedTxt} · callback <a target="_blank" href="${CFG.sepolia.explorer}/address/${CFG.contracts[t.callbackKey]}"><code>${CFG.contracts[t.callbackKey].slice(0, 10)}…</code></a> · vault <a target="_blank" href="${CFG.sepolia.explorer}/address/${CFG.contracts[t.contractKey]}"><code>${CFG.contracts[t.contractKey].slice(0, 10)}…</code></a></li>`);
    }
    el.innerHTML = rows.join("");
  }

  // --- Static facts / proof ---------------------------------------------------------
  function renderFacts() {
    $("netFacts").innerHTML = `
      <li>System contract (Omni): <code>${CFG.systemContract}</code> on Lasna (${CFG.lasna.chainId})</li>
      <li>Sepolia callback proxy: <code>${CFG.sepoliaCallbackProxy}</code></li>
      <li>Callback gas limit: <code>1,000,000</code> · One-shot guard per goal · Reverting reactions are still billed, so <code>react()</code> never reverts as a filter</li>
      <li>Getting test funds: Sepolia ETH from any public faucet; lREACT by sending Sepolia ETH to the faucet contract <code>${CFG.lreactFaucet}</code> (1 ETH → 100 lREACT)</li>`;
    const p = CFG.proof;
    if (p.originTx || p.reactiveTx || p.callbackTx) {
      $("proofTrail").innerHTML = `<h3 class="subhead">Proof trail — one full loop</h3><ul class="facts">
        ${p.originTx ? `<li>Origin deposit (Sepolia): <a target="_blank" href="${CFG.sepolia.explorer}/tx/${p.originTx}">${p.originTx}</a></li>` : ""}
        ${p.reactiveTx ? `<li>Reaction (Lasna): <a target="_blank" href="${CFG.lasna.explorer}/tx/${p.reactiveTx}">${p.reactiveTx}</a></li>` : ""}
        ${p.callbackTx ? `<li>Callback payout (Sepolia): <a target="_blank" href="${CFG.sepolia.explorer}/tx/${p.callbackTx}">${p.callbackTx}</a></li>` : ""}
      </ul>`;
    }
  }

  // --- Wiring -----------------------------------------------------------------------
  document.querySelectorAll("#templatePicker .template[data-template]").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll("#templatePicker .template").forEach((b) => b.classList.remove("selected"));
      btn.classList.add("selected");
      selectedTemplate = btn.dataset.template;
      const t = TEMPLATES[selectedTemplate];
      $("labelBeneficiary").firstChild.textContent = t.beneficiaryLabel + " ";
      $("labelTarget").firstChild.textContent = t.targetLabel + " ";
      renderParams();
    });
  });
  ["fName", "fBeneficiary", "fTarget"].forEach((id) => $(id).addEventListener("input", renderParams));
  $("useMyAddress").addEventListener("click", () => {
    if (signerAddress) { $("fBeneficiary").value = signerAddress; renderParams(); }
    else $("createStatus").textContent = "Connect your wallet first, then this fills itself in.";
  });
  $("connectBtn").addEventListener("click", connectWallet);
  $("createBtn").addEventListener("click", createAutomation);
  $("refreshBtn").addEventListener("click", () => { refreshAutomations(); renderReactiveStatus(); });
  $("depositForm").addEventListener("submit", deposit);
  // Delegated clicks for the per-card Cancel buttons and refund Withdraw buttons.
  document.addEventListener("click", (ev) => {
    const c = ev.target.closest("[data-cancel]");
    if (c) {
      const [tk, id] = c.dataset.cancel.split(":");
      cancelAutomation(tk, Number(id), document.querySelector(`[data-cancel-status="${c.dataset.cancel}"]`));
    }
    const w = ev.target.closest("[data-withdraw]");
    if (w) withdrawRefund(w.dataset.withdraw, w);
  });
  // Wallet account/chain changes invalidate signer state — reload cleanly
  // instead of acting on a stale signer (pre-audit: no listeners at all).
  if (window.ethereum && window.ethereum.on) {
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged", () => location.reload());
  }

  $("previewBanner").classList.toggle("hidden", anyDeployed());
  renderParams();
  renderFacts();
  renderReactiveStatus();
  refreshAutomations();
})();
