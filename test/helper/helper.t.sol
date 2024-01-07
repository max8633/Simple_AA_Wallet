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

// import {MyPaymaster} from "lib/ERC4337-sample/src/MyPaymaster.sol";

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

    address alice = makeAddr("alice");

    address Gurdian1 = makeAddr("Gurdian1");
    address Gurdian2 = makeAddr("Gurdian2");
    address Gurdian3 = makeAddr("Gurdian3");

    address Owner1 = makeAddr("Owner1");
    address Owner2 = makeAddr("Owner2");
    address Owner3 = makeAddr("Owner3");

    // MyPaymaster myPaymaster;

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

        // myPaymaster = new MyPaymaster(IEntryPoint(address(entryPoint)));
        counter = new Counter();
    }
}
