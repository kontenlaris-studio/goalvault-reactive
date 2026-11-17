/* GoalVault dashboard — plain static JS + ethers v6 (CDN). No build step.
 * Reads are done over a public Sepolia RPC (no wallet needed); writes go
 * through the visitor's own wallet (MetaMask etc.) on Sepolia. */
(function () {
  "use strict";
  const CFG = window.GOALVAULT_CONFIG;
  const $ = (id) => document.getElementById(id);

  // --- Template definitions: the low-code layer ------------------------------
  // Adding a template = one entry here + one registry row on-chain.
  const TEMPLATES = {
    goalvault: {
      title: "Savings Goal",
      contractKey: "goalVault",
      reactiveKey: "goalReactiveGoalVault",
      callbackKey: "goalCallbackGoalVault",
      createFn: "createGoal",
      countFn: "goalCount",
      getFn: "getGoal",
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
      countFn: "escrowCount",
      getFn: "getEscrow",
      createdEvent: "EscrowCreated",
      beneficiaryLabel: "Who did the work / who should be paid?",
      targetLabel: "What is the agreed price?",
      partyWord: "Freelancer",
    },
  };

  const VAULT_ABI = [
    "function createGoal(address beneficiary, uint256 target) returns (uint256)",
    "function createEscrow(address freelancer, uint256 target) returns (uint256)",
    "function deposit(uint256 id) payable",
    "function goalCount() view returns (uint256)",
    "function escrowCount() view returns (uint256)",
    "function getGoal(uint256 id) view returns (address, address, uint256, uint256, bool)",
    "function getEscrow(uint256 id) view returns (address, address, uint256, uint256, bool)",
    "event GoalCreated(uint256 indexed goalId, address indexed owner, address indexed beneficiary, uint256 target)",
    "event EscrowCreated(uint256 indexed escrowId, address indexed client, address indexed freelancer, uint256 target)",
  ];

  let selectedTemplate = "goalvault";
  let signer = null;
  let signerAddress = null;
  const readProvider = new ethers.JsonRpcProvider(CFG.sepolia.rpc);

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
    $("createBtn").disabled = !anyDeployed();
  }

  // --- Wallet -----------------------------------------------------------------
  async function connectWallet() {
    if (!window.ethereum) {
      $("walletInfo").textContent = "No wallet found in this browser — install MetaMask to create automations. Browsing still works.";
      return;
    }
    const provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    const net = await provider.getNetwork();
    if (Number(net.chainId) !== CFG.sepolia.chainId) {
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x" + CFG.sepolia.chainId.toString(16) }],
        });
      } catch (e) {
        $("walletInfo").textContent = "Please switch your wallet to Ethereum Sepolia to create automations.";
        return;
      }
    }
    signer = await provider.getSigner();
    signerAddress = await signer.getAddress();
    $("walletInfo").textContent = `Connected: ${signerAddress} · ${CFG.sepolia.name}`;
    $("connectBtn").textContent = "Wallet connected ✓";
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
        const [, party, target, total, done] = await contract[t.getFn](id);
        out.push({ template: key, t, id, party, target, total, done });
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
      const name = store.nameFor(a.template, a.id) || `${a.t.title} #${a.id}`;
      const card = document.createElement("div");
      card.className = "auto";
      card.innerHTML = `
        <div class="top"><h3>${name}</h3>
          <span class="badge ${a.done ? "" : "waiting"}">${a.done ? "✓ Completed — paid out automatically" : "● Watching… set & forget"}</span></div>
        <div class="bar"><div style="width:${pct}%"></div></div>
        <div class="meta">
          <span><strong>${ethers.formatEther(a.total)} / ${ethers.formatEther(a.target)} ETH</strong> (${pct}%)</span>
          <span>${a.t.partyWord}: ${a.party}</span>
          <span>Template: ${a.t.title}</span>
          <span><a target="_blank" href="${CFG.sepolia.explorer}/address/${CFG.contracts[a.t.contractKey]}">Vault on Etherscan ↗</a></span>
        </div>`;
      box.appendChild(card);
      const opt = document.createElement("option");
      opt.value = `${a.template}:${a.id}`;
      opt.textContent = `${name} — ${ethers.formatEther(a.total)}/${ethers.formatEther(a.target)} ETH`;
      if (!a.done) sel.appendChild(opt);
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
  $("refreshBtn").addEventListener("click", refreshAutomations);
  $("depositForm").addEventListener("submit", deposit);

  $("previewBanner").classList.toggle("hidden", anyDeployed());
  renderParams();
  renderFacts();
  refreshAutomations();
})();
