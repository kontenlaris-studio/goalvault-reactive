// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @title MockSystemContract — test double for the Reactive Omni system contract.
/// @notice In production, SYSTEM is the hardcoded address 0x8888...8888 and there is no
///         way to deploy a mock there. In tests we `vm.etch` this contract's code onto
///         0x8888...8888, which lets us (a) satisfy AbstractReactive's `onlySystem`
///         guard by pranking that address as the caller of `react()`, and (b) record
///         every subscription and callback request the reactive contract makes.
/// @dev Implements the exact function signatures of ISystemContract + IPayable's debt().
contract MockSystemContract {
    struct Subscription {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        address subscriber;
    }

    struct CallbackRequest {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
        address sender;
    }

    Subscription[] public subscriptions;
    Subscription[] public unsubscriptions;
    CallbackRequest[] public callbackRequests;
    uint256 public legacyCallbackCount;

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        subscriptions.push(
            Subscription({
                chainId: chainId_,
                contractAddress: contract_,
                topic0: topic0_,
                topic1: topic1_,
                topic2: topic2_,
                topic3: topic3_,
                subscriber: msg.sender
            })
        );
    }

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        unsubscriptions.push(
            Subscription({
                chainId: chainId_,
                contractAddress: contract_,
                topic0: topic0_,
                topic1: topic1_,
                topic2: topic2_,
                topic3: topic3_,
                subscriber: msg.sender
            })
        );
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        callbackRequests.push(
            CallbackRequest({
                chainId: config_.chainId,
                recipient: config_.recipient,
                gasLimit: config_.gasLimit,
                payload: config_.payload,
                sender: msg.sender
            })
        );
    }

    function requestCallback(ISystemContract.CallbackVersion, bytes memory) external {
        legacyCallbackCount++;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable { }

    // --- Test helpers ---
    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function unsubscriptionCount() external view returns (uint256) {
        return unsubscriptions.length;
    }

    function callbackRequestCount() external view returns (uint256) {
        return callbackRequests.length;
    }

    function lastCallbackRequest()
        external
        view
        returns (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload, address sender)
    {
        CallbackRequest storage r = callbackRequests[callbackRequests.length - 1];
        return (r.chainId, r.recipient, r.gasLimit, r.payload, r.sender);
    }
}
