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
        vm.deal(bundler, 20 ether);
        vm.deal(address(entryPoint), 20 ether);
        console2.log("entrypoint: ", address(entryPoint).balance);

        vm.startPrank(owners[0]);
        entryPoint.depositTo{value: 20 ether}(address(wallet));
        assertEq(entryPoint.balanceOf(address(wallet)), 20 ether);
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
}
