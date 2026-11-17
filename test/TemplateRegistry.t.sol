// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { TemplateRegistry } from "../src/sepolia/TemplateRegistry.sol";

contract TemplateRegistryTest is Test {
    TemplateRegistry internal registry;
    address internal vault = makeAddr("vault");
    address internal callback = makeAddr("callback");

    function setUp() public {
        registry = new TemplateRegistry();
    }

    function test_RegisterAndRead() public {
        uint256 id = registry.registerTemplate("Savings Goal", "goalvault", vault, callback);
        assertEq(id, 0);
        assertEq(registry.templateCount(), 1);
        (string memory name, string memory kind, address v, address c, bool active) = registry.getTemplate(0);
        assertEq(name, "Savings Goal");
        assertEq(kind, "goalvault");
        assertEq(v, vault);
        assertEq(c, callback);
        assertTrue(active);
    }

    function test_Register_OnlyOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(TemplateRegistry.NotOwner.selector);
        registry.registerTemplate("X", "x", vault, callback);
    }

    function test_SetActive() public {
        registry.registerTemplate("Pay When Funded", "escrow", vault, callback);
        registry.setTemplateActive(0, false);
        (,,,, bool active) = registry.getTemplate(0);
        assertFalse(active);
    }
}
