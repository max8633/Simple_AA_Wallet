// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Helper} from "test/helper/helper.t.sol";
import {Wallet} from "src/wallet.sol";
import {WalletFactory} from "src/walletFactory.sol";
import {Counter} from "src/Counter.sol";

contract WalletTest is Helper {
    function setUp() public override {
        super.setUp();
    }

    function testReceive() public {
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        (bool success, ) = address(wallet).call{value: 1 ether}("");
        require(success, "transfer ether failed");
        vm.stopPrank();

        assertEq(address(wallet).balance, INIT_BALANCE + 1 ether);
        assertEq(alice.balance, 0);
    }

    function testSubmitSingleTransactionByOwner() public {
        vm.startPrank(owners[0]);
        (
            address[] memory toSingle,
            uint256[] memory valueSingle,
            bytes[] memory dataSingle
        ) = singleTransactionSetUp();
        uint256 txnId = wallet.submitTransaction(
            toSingle,
            valueSingle,
            dataSingle
        );
        vm.stopPrank();
        assertEq(txnId, 1);

        (
            address[] memory to,
            uint256[] memory value,
            bytes[] memory data,
            bool[] memory executed,
            uint256[] memory transactionId
        ) = wallet.getTransactionInfo(1);

        assertEq(to[0], address(counter));
        assertEq(value[0], 0);
        assertEq(data[0], abi.encodeCall(counter.increment, ()));
    }

    function testConfirmSingleTransaction() public {
        vm.startPrank(owners[0]);
        (
            address[] memory to,
            uint256[] memory value,
            bytes[] memory data
        ) = singleTransactionSetUp();
        uint256 txnId = wallet.submitTransaction(to, value, data);
        vm.stopPrank();

        vm.startPrank(owners[1]);
        wallet.confirmTransaction(1);

        uint256 confirmednum = wallet.isTransactionConfirmedAlready(1);

        assertEq(confirmednum, 2);
    }

    function testExecuteSingleTransaction() public {
        vm.startPrank(owners[0]);
        (
            address[] memory to,
            uint256[] memory value,
            bytes[] memory data
        ) = singleTransactionSetUp();
        uint256 txnId = wallet.submitTransaction(to, value, data);
        vm.stopPrank();

        vm.prank(owners[1]);
        wallet.confirmTransaction(1);

        vm.startPrank(owners[2]);
        wallet.confirmTransaction(1);

        uint256 confirmednum = wallet.isTransactionConfirmedAlready(1);
        assertEq(confirmednum, 3);

        bool success = wallet.executeTransaction(1);
        require(success == true, "execute transaction fail");
        assertEq(counter.number(), 1);
        assertEq(address(counter).balance, 0);
    }

    function testSubmitBatchTransactionByOwner() public {
        vm.startPrank(owners[0]);
        (
            address[] memory toBatch,
            uint256[] memory valueBatch,
            bytes[] memory dataBatch
        ) = batchTransactionSetUp();
        uint256 txnId = wallet.submitTransaction(
            toBatch,
            valueBatch,
            dataBatch
        );
        vm.stopPrank();
        assertEq(txnId, 1);

        (
            address[] memory to,
            uint256[] memory value,
            bytes[] memory data,
            bool[] memory executed,
            uint256[] memory transactionId
        ) = wallet.getTransactionInfo(1);

        assertEq(to[0], address(counter));
        assertEq(value[0], 0);
        assertEq(data[0], abi.encodeCall(counter.increment, ()));
        assertEq(to[1], address(counter));
        assertEq(value[1], 0);
        assertEq(data[1], abi.encodeCall(counter.increment, ()));
    }

    function testConfirmBatchTransaction() public {
        vm.startPrank(owners[0]);
        (
            address[] memory toBatch,
            uint256[] memory valueBatch,
            bytes[] memory dataBatch
        ) = batchTransactionSetUp();
        uint256 txnId = wallet.submitTransaction(
            toBatch,
            valueBatch,
            dataBatch
        );
        vm.stopPrank();

        vm.startPrank(owners[1]);
        wallet.confirmTransaction(1);

        uint256 confirmednum = wallet.isTransactionConfirmedAlready(1);
        assertEq(confirmednum, 2);

        vm.stopPrank();
    }

    function testExecuteBatchTransaction() public {
        vm.startPrank(owners[0]);
        (
            address[] memory toBatch,
            uint256[] memory valueBatch,
            bytes[] memory dataBatch
        ) = batchTransactionSetUp();
        uint256 txnId = wallet.submitTransaction(
            toBatch,
            valueBatch,
            dataBatch
        );
        vm.stopPrank();

        vm.prank(owners[1]);
        wallet.confirmTransaction(1);

        vm.startPrank(owners[2]);
        wallet.confirmTransaction(1);

        uint256 confirmednum = wallet.isTransactionConfirmedAlready(1);
        assertEq(confirmednum, 3);

        bool success = wallet.executeTransaction(1);
        require(success == true, "execute transaction fail");
        assertEq(counter.number(), 2);
        assertEq(address(counter).balance, 0);
    }

    function testInitiateRecovery() public {
        address newOwner = makeAddr("newOwner");
        vm.startPrank(gurdians[0]);
        wallet.initialRecovery(owners[0], newOwner);
        vm.stopPrank();

        assertEq(wallet.currentRecoveryRound(), 1);
        assertEq(wallet.isRecovery(), true);
    }

    function testSupportRecovery() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(gurdians[0]);
        wallet.initialRecovery(owners[0], newOwner);

        vm.startPrank(gurdians[1]);
        wallet.supportRecovery(owners[0], newOwner);

        (
            address newOwnerAddr,
            uint256 recoveryRound,
            bool usedInExecuteRecovery
        ) = wallet.getRecoveryInfo();
        assertEq(newOwnerAddr, newOwner);
        assertEq(recoveryRound, 1);
        assertEq(usedInExecuteRecovery, false);

        vm.stopPrank();
    }

    function testExecuteRecovery() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(gurdians[0]);
        wallet.initialRecovery(owners[0], newOwner);

        vm.prank(gurdians[1]);
        wallet.supportRecovery(owners[0], newOwner);

        vm.prank(gurdians[2]);
        wallet.supportRecovery(owners[0], newOwner);

        vm.warp(block.timestamp + 5 days);

        vm.startPrank(gurdians[0]);
        address[] memory walletOwners = wallet.executeRecovery(
            owners[0],
            newOwner,
            gurdians
        );

        assertEq(walletOwners[0], newOwner);
        assertEq(wallet.isRecovery(), false);
        assertEq(wallet.isOwner(newOwner), true);
    }

    function testCancelRecovery() public {
        address newOwner = makeAddr("newOwner");
        vm.startPrank(gurdians[0]);
        wallet.initialRecovery(owners[0], newOwner);
        assertEq(wallet.isRecovery(), true);
        vm.stopPrank();

        vm.startPrank(owners[0]);
        wallet.cancelRecovery();
        assertEq(wallet.isRecovery(), false);
        vm.stopPrank();

        vm.startPrank(gurdians[1]);
        vm.expectRevert();
        wallet.supportRecovery(owners[0], newOwner);
        vm.stopPrank();
    }

    function testInitiateGurdianRemoval() public {
        vm.startPrank(owners[0]);

        wallet.initiateGurdianRemoval(gurdians[2]);

        assertEq(wallet.inGurdianUpdate(), true);
    }

    function testSupportGurdianRemoval() public {
        vm.prank(owners[0]);
        wallet.initiateGurdianRemoval(gurdians[2]);

        vm.prank(owners[1]);
        wallet.supportGurdianRemoval(gurdians[2]);

        assertEq(wallet.supportToGurdianRemoval(), 2);
    }

    function testSupportThenExecuteGurdianRemoval() public {
        vm.prank(owners[0]);
        wallet.initiateGurdianRemoval(gurdians[2]);

        vm.prank(owners[1]);
        wallet.supportGurdianRemoval(gurdians[2]);

        vm.warp(block.timestamp + 5 days);

        vm.prank(owners[2]);
        wallet.supportGurdianRemoval(gurdians[2]);

        uint256 walletGurdiansLength = wallet.executeGurdianRemoval(
            gurdians[2]
        );
        assertEq(walletGurdiansLength, wallet.threshold());
    }

    function testInitiateGurdianUpdate() public {
        address newGurdian = makeAddr("newGurdian");

        vm.prank(owners[0]);
        wallet.initiateGurdianUpdate(gurdians[0], newGurdian);

        assertEq(wallet.inGurdianUpdate(), true);
    }

    function testSupportGurdianUpdate() public {
        address newGurdian = makeAddr("newGurdian");

        vm.prank(owners[0]);
        wallet.initiateGurdianUpdate(gurdians[0], newGurdian);

        vm.prank(owners[1]);
        wallet.supportGurdianUpdate(gurdians[0], newGurdian);

        assertEq(wallet.supportToGurdianUpdate(), 2);
    }

    function testExecuteGurdianUpdate() public {
        address newGurdian = makeAddr("newGurdian");

        vm.prank(owners[0]);
        wallet.initiateGurdianUpdate(gurdians[0], newGurdian);

        vm.prank(owners[1]);
        wallet.supportGurdianUpdate(gurdians[0], newGurdian);

        vm.warp(block.timestamp + 5 days);

        vm.prank(owners[2]);

        wallet.supportGurdianUpdate(gurdians[0], newGurdian);
        address[] memory walletGurdians = wallet.executeGurdianUpdate(
            gurdians[0],
            newGurdian
        );

        assertEq(wallet.inGurdianUpdate(), false);
        assertEq(walletGurdians[0], newGurdian);
        assertEq(wallet.isGurdian(newGurdian), true);
    }
}
