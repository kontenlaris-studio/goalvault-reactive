// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title TemplateRegistry — the on-chain catalogue behind the low-code dashboard.
/// @notice The dashboard is a template gallery: each entry here describes one automation
///         template (its vault + callback wiring on Sepolia). Registering a new template
///         is all it takes for it to appear in the builder — no dashboard code change.
///         Templates #1 (GoalVault) and #2 (EscrowVault) are registered after deployment;
///         see deployments.md.
contract TemplateRegistry {
    struct Template {
        string name; // e.g. "Savings Goal"
        string kind; // e.g. "goalvault" | "escrow" — the dashboard form key
        address vault; // origin vault on Sepolia
        address callback; // GoalCallback instance wired to that vault
        bool active;
    }

    address public owner;
    Template[] public templates;

    event TemplateRegistered(uint256 indexed templateId, string name, string kind, address indexed vault);
    event TemplateActiveSet(uint256 indexed templateId, bool active);

    error NotOwner();
    error InvalidVault();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerTemplate(string calldata name, string calldata kind, address vault, address callback_)
        external
        onlyOwner
        returns (uint256 templateId)
    {
        if (vault == address(0)) revert InvalidVault();
        templateId = templates.length;
        templates.push(Template({ name: name, kind: kind, vault: vault, callback: callback_, active: true }));
        emit TemplateRegistered(templateId, name, kind, vault);
    }

    function setTemplateActive(uint256 templateId, bool active) external onlyOwner {
        templates[templateId].active = active;
        emit TemplateActiveSet(templateId, active);
    }

    function templateCount() external view returns (uint256) {
        return templates.length;
    }

    function getTemplate(uint256 templateId)
        external
        view
        returns (string memory name, string memory kind, address vault, address callback, bool active)
    {
        Template storage t = templates[templateId];
        return (t.name, t.kind, t.vault, t.callback, t.active);
    }
}
