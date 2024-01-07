// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Counter} from "src/Counter.sol";
import {Wallet} from "src/wallet.sol";
import {WalletFactory} from "src/walletFactory.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {MyPaymaster} from "lib/ERC4337-sample/src/MyPaymaster.sol";

contract Helper is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    uint256 constant ownersNum = 3;
    uint256 constant numOfConfirmRequired = 2;
    uint256 constant gurdiansNum = 3;
    uint256 constant threshold = 2;
    uint256 constant salt = 1;

    address[] public owners = new address[](ownersNum);
    address[] public gurdians = new address[](gurdiansNum);

    Wallet wallet;
    WalletFactory walletFactory;
    EntryPoint entryPoint;
    Counter counter;
    MyPaymaster myPaymaster;

    address alice = makeAddr("alice");

    address Gurdian1 = makeAddr("Gurdian1");
    address Gurdian2 = makeAddr("Gurdian2");
    address Gurdian3 = makeAddr("Gurdian3");

    address Owner1 = makeAddr("Owner1");
    address Owner2 = makeAddr("Owner2");
    address Owner3 = makeAddr("Owner3");

    function setUp() public virtual {
        gurdians[0] = Gurdian1;
        gurdians[1] = Gurdian2;
        gurdians[2] = Gurdian3;

        owners[0] = Owner1;
        owners[1] = Owner2;
        owners[2] = Owner3;

        entryPoint = new EntryPoint();

        walletFactory = new WalletFactory(entryPoint);
        wallet = walletFactory.createAccount(
            owners,
            numOfConfirmRequired,
            gurdians,
            threshold,
            salt
        );
        assertEq(wallet.numOfConfirmRequired(), numOfConfirmRequired);

        myPaymaster = new MyPaymaster(IEntryPoint(address(entryPoint)));
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
}
