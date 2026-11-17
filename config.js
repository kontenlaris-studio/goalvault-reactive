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
    goalVault: "", // GoalVault on Sepolia
    escrowVault: "", // EscrowVault on Sepolia
    templateRegistry: "", // TemplateRegistry on Sepolia
    goalReactiveGoalVault: "", // GoalReactive for GoalVault, on Lasna
    goalReactiveEscrowVault: "", // GoalReactive for EscrowVault, on Lasna
    goalCallbackGoalVault: "", // GoalCallback for GoalVault, on Sepolia
    goalCallbackEscrowVault: "", // GoalCallback for EscrowVault, on Sepolia
  },
  proof: {
    originTx: "", // Sepolia tx where the target-crossing deposit landed
    reactiveTx: "", // Lasna tx where react() requested the callback
    callbackTx: "", // Sepolia tx where the callback released the funds
  },
};
