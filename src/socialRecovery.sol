// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {TokenCallbackHandler} from "lib/account-abstraction/contracts/samples/callback/TokenCallbackHandler.sol";

contract Recovery is ReentrancyGuard, TokenCallbackHandler {
    //@notice chech address is gurdian
    mapping(address => bool) isGurdian;

    //@notice store gurdians threshold
    uint256 public threshold;

    //@notice owners of the wallet
    address[] public owners;

    mapping(address => bool) public isOwner;

    //@notice check if in recovery
    bool public isRecovery;

    //@notice store current recovery round
    uint256 public currentRecoveryRound;

    struct Recovery {
        address newOwnerAddr;
        uint256 recoveryRound;
        bool usedInExecuteRecovery;
    }

    mapping(address => Recovery) recoveryInfo;

    modifier onlyOwners() {
        require(isOwner[msg.sender], "Only owner");
        _;
    }

    modifier onlyGurdians() {
        require(isGurdian[msg.sender], "Only Gurdian");
        _;
    }

    modifier onlyInRecovery() {
        require(isRecovery, "not in recovery");
        _;
    }

    modifier notInRecovery() {
        require(!isRecovery, "is in recovery now");
        _;
    }

    constructor(address[] memory _owners, uint256 _threshold) {
        threshold = _threshold;
        for (uint256 i = 0; i < _owners.length; i++) {
            owners[i] = _owners[i];
            isOwner[owners[i]] = true;
        }
    }

    function initialRecovery(
        address oldOwner,
        address newOwner
    ) external onlyGurdians notInRecovery {
        currentRecoveryRound++;
        recoveryInfo[msg.sender] = Recovery(
            newOwner,
            currentRecoveryRound,
            false
        );
        isRecovery = true;
    }

    function supportRecovery(
        address newOwner
    ) external onlyGurdians onlyInRecovery {
        recoveryInfo[msg.sender] = Recovery(
            newOwner,
            currentRecoveryRound,
            false
        );
    }

    function cancelRecovery() external onlyOwners onlyInRecovery {
        isRecovery = false;
    }

    function executeRecovery(
        address newOwner,
        address[] calldata gurdiansList
    ) external onlyGurdians onlyInRecovery {}
}
