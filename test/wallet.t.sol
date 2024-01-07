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

        address[] memory a;
    }

    function testReceive() public {
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        (bool success, ) = address(wallet).call{value: 1 ether}("");
        require(success, "transfer ether failed");
        vm.stopPrank();

        assertEq(address(wallet).balance, 1 ether);
        assertEq(alice.balance, 0);
    }

    // function testSubmitTransactionByOwner() public {
    //     vm.startPrank(owners[0]);

    //     uint256 txnId = wallet.submitTransaction(to, value, data);
    //     vm.stopPrank();

    //     assertEq(txnId, 0);
    // }

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
        wallet.executeRecovery(owners[0], newOwner, gurdians);

        // assertEq(owners[0], newOwner);
        assertEq(wallet.isRecovery(), false);
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

        assertEq(gurdians[2], address(0));
    }

    function testInitiateGurdianUpdate() public {
        address newGurdian = makeAddr("newGurdian");

        vm.prank(owners[0]);
        wallet.initiateGurdianUpdate(gurdians[0], newGurdian);

        assertEq(wallet.inGurdianUpdate(), true);
    }

    // function testSupportGurdianUpdate() public {
    //     address newGurdian = makeAddr("newGurdian");

    //     vm.prank(owners[0]);
    //     wallet.initiateGurdianUpdate(gurdians[0], newGurdian);

    //     vm.prank(owners[1]);
    //     wallet.supportGurdianUpdate(gurdians[0], newGurdian);

    //     assertEq(wallet.supportToGurdianUpdate(), 2);
    // }

    // function testSupportThenExecuteGurdianUpdate() public {
    //     address newGurdian = makeAddr("newGurdian");

    //     vm.prank(owners[0]);
    //     wallet.initiateGurdianUpdate(wallet.gurdians[0], newGurdian);

    //     vm.prank(owners[1]);
    //     wallet.supportGurdianUpdate(wallet.gurdians[0], newGurdian);

    //     vm.warp(block.timestamp + 5 days);

    //     vm.prank(owners[2]);
    //     wallet.supportGurdianUpdate(wallet.gurdians[0], newGurdian);
    //     wallet.executeGurdianUpdate(wallet.gurdians[0], newGurdian);

    //     assertEq(wallet.inGurdianUpdate(), false);
    //     assertEq(wallet.gurdians[0], newGurdian);
    // }

    function testA() public {
        address newGurdian = makeAddr("newGurdian");
        console2.log("a:", newGurdian);
        address[] memory walletGurdians = wallet.getGurdians();
        wallet.executeGurdianUpdate(walletGurdians[0], newGurdian);
        console2.log(gurdians[0], walletGurdians[0]);
        assertEq(walletGurdians[0], newGurdian);
    }
}
