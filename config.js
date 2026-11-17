/* ============================================================================
 * GoalVault — deployment configuration
 * ----------------------------------------------------------------------------
 * After the deployment stage, paste the deployed addresses + tx hashes here.
 * The dashboard reads everything else (vault state, progress, completion)
 * live from the Sepolia RPC — no server, no build step.
 *
 * Until `contracts.goalVault` / `contracts.escrowVault` are filled in, the
 * dashboard runs in PREVIEW mode: the builder form and the generated
 * deployment parameters work fully, but on-chain creation is disabled.
 * ========================================================================== */
window.GOALVAULT_CONFIG = {
  // Networks (verified in BUILD-PLAN.md, re-verify chain IDs before deploying)
  sepolia: {
    chainId: 11155111,
    name: "Ethereum Sepolia",
    rpc: "https://ethereum-sepolia-rpc.publicnode.com",
    explorer: "https://sepolia.etherscan.io",
  },
  lasna: {
    chainId: 5318007,
    name: "Reactive Lasna",
    rpc: "https://lasna-rpc.rnk.dev/",
    explorer: "https://lasna.reactscan.net",
  },

  // Reactive Omni constants
  systemContract: "0x8888888888888888888888888888888888888888",
  sepoliaCallbackProxy: "0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4",
  lreactFaucet: "0x9b9BB25f1A81078C544C829c5EB7822d747Cf434", // send Sepolia ETH, get lREACT 1:100
  depositedTopic0: "0x893e8a14c42d0303c66e296f4c3e4ed772edf8097f8d41ab8d08099654172ec0", // keccak256("Deposited(uint256,address,uint256,uint256,uint256)") via `cast keccak`

  // === FILLED IN AT DEPLOYMENT TIME (see deployments.md) ===
  contracts: {
    goalVault: "0x974465f83CC332810d475b1092F96A4376434eCD", // GoalVault on Sepolia
    escrowVault: "0x942e0d1cCB31B6C4a12E6b479D6F406C644DeE8E", // EscrowVault on Sepolia
    templateRegistry: "0x4a30CD68D2046E37f3f8cF81431d743c0b227400", // TemplateRegistry on Sepolia
    goalReactiveGoalVault: "0x24dB62b02e0D6Fd5863ab554e08aE61A44604e0D", // GoalReactive for GoalVault, on Lasna
    goalReactiveEscrowVault: "0x974465f83CC332810d475b1092F96A4376434eCD", // GoalReactive for EscrowVault, on Lasna
    goalCallbackGoalVault: "0xfC568793c7f2a04178F4809c10312D98E61e33f1", // GoalCallback for GoalVault, on Sepolia
    goalCallbackEscrowVault: "0xc772B94E8f61A3BF98A450a85aB11606190432D0", // GoalCallback for EscrowVault, on Sepolia
  },
  proof: {
    originTx: "0x34237a26af37c319c7a8dbc24ee7ace2e7fcca237c8c5cc47afa112945152ef3", // Sepolia tx where the target-crossing deposit landed
    reactiveTx: "0x134498f8fde439857db7db8df0dfaff5105e1690f72526017a1b3b63340e30e0", // Lasna tx where react() requested the callback
    callbackTx: "0xdb51a1193e9d33c74105b955852305e189f1019ef7abbbf64563a918047ca892", // Sepolia tx where the callback released the funds
  },
};
