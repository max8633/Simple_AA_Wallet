// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Helper} from "test/helper/helper.t.sol";
import {Wallet} from "src/wallet.sol";
import {WalletFactory} from "src/walletFactory.sol";
import {Counter} from "src/Counter.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserOperation, UserOperationLib} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";

contract WalletInteractWithEntryPointTest is Helper {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using UserOperationLib for UserOperation;

    function setUp() public override {
        super.setUp();

        bundler = makeAddr("bundler");
        vm.deal(bundler, 100 ether);
        vm.deal(address(entryPoint), 100 ether);
        console2.log("entrypoint: ", address(entryPoint).balance);

        vm.startPrank(owners[0]);
        entryPoint.depositTo{value: 10 ether}(address(wallet));
        assertEq(entryPoint.balanceOf(address(wallet)), 10 ether);
        console2.log("wallet: ", entryPoint.balanceOf(address(wallet)));

        vm.stopPrank();
    }

    function testEntryPointTransferETH() public {
        //create UserOperation
        vm.startPrank(owners[0]);
        UserOperation memory ops = createUserOp(address(wallet));
        ops.callData = abi.encodeCall(
            wallet.execute,
            (alice, 1 ether, bytes(""))
        );

        //sign
        bytes32 userOpHash = entryPoint.getUserOpHash(ops);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKeys[0], digest);
        ops.signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        UserOperation[] memory userOps;
        userOps = new UserOperation[](1);
        userOps[0] = ops;

        //bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(userOps, payable(bundler));

        assertEq(alice.balance, 1 ether);
        vm.stopPrank();
    }

    function testEntryPointCreateWallet() public {
        //create UserOperation
        vm.startPrank(owners[0]);
        address sender = walletFactory.getAddress(
            owners,
            numOfConfirmRequired,
            gurdians,
            threshold,
            5
        );
        bytes memory initData = abi.encodeCall(
            walletFactory.createAccount,
            (owners, numOfConfirmRequired, gurdians, threshold, 5)
        );

        UserOperation memory ops = createUserOp(sender);
        ops.initCode = abi.encodePacked(address(walletFactory), initData);
        ops.callData = abi.encodeCall(
            wallet.execute,
            (alice, 1 ether, bytes(""))
        );

        //sign
        bytes32 userOpHash = entryPoint.getUserOpHash(ops);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKeys[0], digest);
        ops.signature = abi.encodePacked(r, s, v);
        entryPoint.depositTo{value: 5 ether}(sender);
        assertEq(entryPoint.balanceOf(sender), 5 ether);

        vm.stopPrank();

        UserOperation[] memory userOps;
        userOps = new UserOperation[](1);
        userOps[0] = ops;

        vm.prank(bundler);
        entryPoint.handleOps(userOps, payable(bundler));

        //check do initialize already
        assertEq((Wallet(payable(sender))).isInitAlready(), true);
        //pay gas fee with ether we deposit before
        assertLt(entryPoint.balanceOf(address(sender)), 5 ether);
    }

    function testEntryPointSubmitTransaction() public {
        //create UserOperation
        vm.startPrank(owners[0]);
        UserOperation memory ops = createUserOp(address(wallet));
        (
            address[] memory toSingle,
            uint256[] memory valueSingle,
            bytes[] memory dataSingle
        ) = singleTransactionSetUp();

        ops.callData = abi.encodeCall(
            wallet.submitTransaction,
            (toSingle, valueSingle, dataSingle, owners[0])
        );

        //sign
        bytes32 userOpHash = entryPoint.getUserOpHash(ops);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKeys[0], digest);
        ops.signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        UserOperation[] memory userOps;
        userOps = new UserOperation[](1);
        userOps[0] = ops;

        //bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(userOps, payable(bundler));

        (
            address[] memory to,
            uint256[] memory value,
            bytes[] memory data
        ) = wallet.getTransactionInfo(1);

        assertEq(to[0], address(counter));
        assertEq(value[0], 0);
        assertEq(data[0], abi.encodeCall(counter.increment, ()));
    }

    function testEntryPointConfirmTransaction() public {
        //create UserOperation of submit transaction
        testEntryPointSubmitTransaction();
        //create UserOperation of confirm transaction
        vm.startPrank(owners[1]);
        UserOperation memory ops = createUserOp(address(wallet));

        ops.callData = abi.encodeCall(
            wallet.confirmTransaction,
            (owners[1], 1)
        );

        //sign
        bytes32 userOpHash = entryPoint.getUserOpHash(ops);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKeys[1], digest);
        ops.signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        UserOperation[] memory userOps;
        userOps = new UserOperation[](1);
        userOps[0] = ops;

        //bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(userOps, payable(bundler));

        uint256 confirmednum = wallet.isTransactionConfirmedAlready(1);
        assertEq(confirmednum, 2);
    }

    function testExecuteTransactionFromEntryPoint() public {
        //create UserOperation of submit transaction
        testEntryPointSubmitTransaction();
        //create UserOperation of confirm transaction
        confirmEntryPointTransction(owners[1], ownerKeys[1]);
        confirmEntryPointTransction(owners[2], ownerKeys[2]);

        uint256 confirmednum = wallet.isTransactionConfirmedAlready(1);
        assertEq(confirmednum, 3);

        vm.startPrank(owners[1]);
        UserOperation memory ops = createUserOp(address(wallet));

        ops.callData = abi.encodeCall(wallet.executeTransaction, (1));

        //sign
        bytes32 userOpHash = entryPoint.getUserOpHash(ops);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKeys[1], digest);
        ops.signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        UserOperation[] memory userOps;
        userOps = new UserOperation[](1);
        userOps[0] = ops;

        //bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(userOps, payable(bundler));

        assertEq(counter.number(), 1);
        assertEq(address(counter).balance, 0);
    }

    function confirmEntryPointTransction(
        address owner,
        uint256 ownerKey
    ) public {
        vm.startPrank(owner);
        UserOperation memory ops = createUserOp(address(wallet));

        ops.callData = abi.encodeCall(wallet.confirmTransaction, (owner, 1));

        //sign
        bytes32 userOpHash = entryPoint.getUserOpHash(ops);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        ops.signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        UserOperation[] memory userOps;
        userOps = new UserOperation[](1);
        userOps[0] = ops;

        //bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(userOps, payable(bundler));
    }
}
