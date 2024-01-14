// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Counter} from "src/Counter.sol";
import {Wallet} from "src/wallet.sol";
import {WalletFactory} from "src/walletFactory.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation, UserOperationLib} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

// import {MyPaymaster} from "lib/ERC4337-sample/src/MyPaymaster.sol";

contract Helper is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using UserOperationLib for UserOperation;

    uint256 constant ownersNum = 3;
    uint256 constant numOfConfirmRequired = 2;
    uint256 constant gurdiansNum = 3;
    uint256 constant threshold = 2;
    uint256 constant salt = 1;

    address bundler;

    address[] public owners = new address[](ownersNum);
    uint256[] public ownerKeys = new uint256[](ownersNum);

    address[] public gurdians = new address[](gurdiansNum);
    uint256[] public gurdianKeys = new uint256[](gurdiansNum);

    Wallet wallet;
    WalletFactory walletFactory;
    EntryPoint entryPoint;
    Counter counter;
    // MyPaymaster myPaymaster;

    address alice = makeAddr("alice");

    function setUp() public virtual {
        (address Gurdian1, uint256 gurdianPrivateKey1) = makeAddrAndKey(
            "Gurdian1"
        );
        (address Gurdian2, uint256 gurdianPrivateKey2) = makeAddrAndKey(
            "Gurdian2"
        );
        (address Gurdian3, uint256 gurdianPrivateKey3) = makeAddrAndKey(
            "Gurdian3"
        );

        gurdians[0] = Gurdian1;
        gurdians[1] = Gurdian2;
        gurdians[2] = Gurdian3;

        gurdianKeys[0] = gurdianPrivateKey1;
        gurdianKeys[1] = gurdianPrivateKey2;
        gurdianKeys[2] = gurdianPrivateKey3;

        vm.deal(gurdians[0], 20 ether);
        vm.deal(gurdians[1], 20 ether);
        vm.deal(gurdians[2], 20 ether);

        (address Owner1, uint256 ownerPrivateKey1) = makeAddrAndKey("Owner1");
        (address Owner2, uint256 ownerPrivateKey2) = makeAddrAndKey("Owner2");
        (address Owner3, uint256 ownerPrivateKey3) = makeAddrAndKey("Owner3");

        owners[0] = Owner1;
        owners[1] = Owner2;
        owners[2] = Owner3;

        ownerKeys[0] = ownerPrivateKey1;
        ownerKeys[1] = ownerPrivateKey2;
        ownerKeys[2] = ownerPrivateKey3;

        vm.deal(owners[0], 20 ether);
        vm.deal(owners[1], 20 ether);
        vm.deal(owners[2], 20 ether);

        entryPoint = new EntryPoint();

        walletFactory = new WalletFactory(entryPoint);
        wallet = walletFactory.createAccount(
            owners,
            numOfConfirmRequired,
            gurdians,
            threshold,
            salt
        );
        vm.deal(address(wallet), 20 ether);
        assertEq(address(wallet).balance, 20 ether);
        assertEq(wallet.numOfConfirmRequired(), numOfConfirmRequired);

        // myPaymaster = new MyPaymaster(IEntryPoint(address(entryPoint)));
        counter = new Counter();
    }

    function singleTransactionSetUp()
        public
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address[] memory to = new address[](1);
        uint256[] memory value = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        to[0] = address(counter);
        value[0] = 0;
        data[0] = abi.encodeCall(counter.increment, ());
        return (to, value, data);
    }

    function batchTransactionSetUp()
        public
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address[] memory toBatch = new address[](2);
        toBatch[0] = address(counter);
        toBatch[1] = address(counter);
        uint256[] memory valueBatch = new uint256[](2);
        valueBatch[0] = 0;
        valueBatch[1] = 0;
        bytes[] memory dataBatch = new bytes[](2);
        dataBatch[0] = abi.encodeCall(counter.increment, ());
        dataBatch[1] = abi.encodeCall(counter.increment, ());
        return (toBatch, valueBatch, dataBatch);
    }

    function createUserOp(
        address sender
    ) internal view returns (UserOperation memory) {
        return
            UserOperation({
                sender: sender,
                nonce: wallet.getNonce(),
                initCode: bytes(""),
                callData: bytes(""),
                callGasLimit: 1_000_000,
                verificationGasLimit: 1_000_000,
                preVerificationGas: 1_000_000,
                maxFeePerGas: 10_000_000_000,
                maxPriorityFeePerGas: 2_500_000_000,
                paymasterAndData: bytes(""),
                signature: bytes("")
            });
    }
}
