// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {BaseAccount} from "lib/account-abstraction/contracts/core/BaseAccount.sol";
import {UserOperation} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import {TokenCallbackHandler} from "lib/account-abstraction/contracts/samples/callback/TokenCallbackHandler.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Wallet is
    BaseAccount,
    Initializable,
    UUPSUpgradeable,
    TokenCallbackHandler,
    ReentrancyGuard
{
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address[] public owners;

    address public immutable walletFactory;

    IEntryPoint private immutable _entryPoint;

    uint256 numOfConfirmRequired;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 transactionId;
    }

    //@notice use for store recovery info
    struct Recovery {
        address newOwnerAddr;
        uint256 recoveryRound;
        bool usedInExecuteRecovery;
    }

    mapping(uint256 => mapping(address => bool)) isConfirmed;

    mapping(addres => bool) inBlackList;

    uint256 public currentTransationNum;

    mapping(uint256 => Transaction[]) transactions;

    //@notice chech address is gurdian
    mapping(address => bool) isGurdian;

    //@notice store gurdians threshold
    uint256 public threshold;

    //@notice owners of the wallet
    address[] public gurdians;

    //@notice check owner address cant use for twice
    mapping(address => bool) internal noLongerOwners;

    //@notice check is address is owners
    mapping(address => bool) public isOwners;

    //@notice store the time a new recovery process initiate
    mapping(uint256 => uint256) public executeRecoveryTimestamp;

    mapping(address => uint256) public gurdianToRemovalTimestamp;

    //@notice check if in recovery
    bool public isRecovery;

    //@notice store current recovery round
    uint256 public currentRecoveryRound;

    //@notice store gurdians's support info of recovery
    mapping(address => Recovery) recoveryInfo;

    event WalletInitialized(
        IEntryPoint indexed entryPoint,
        address[] owners,
        uint256 numOfConfirmRequired,
        address[] gurdians,
        uint256 threshold
    );

    modifier _requireCalledByEntryPointOrWalletFactory() {
        require(
            msg.sender == address(_entryPoint) || msg.sender == walletFactory,
            "only entry point and wallet factory can call"
        );
        _;
    }

    modifier onlyOwners() {
        require(isOwners[msg.sender], "Only owner");
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

    constructor(IEntryPoint EntryPoint, address WalletFactory_) {
        _entryPoint = EntryPoint;
        walletFactory = WalletFactory_;
    }

    function _authorizeUpgrade(
        address
    ) internal view override _requireCalledByEntryPointOrWalletFactory {}

    function entryPoint() public view override returns (IEntryPoint) {
        return _entryPoint;
    }

    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view override returns (uint256) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        bytes[] memory signatures = abi.decode(userOp.signature, (bytes[]));

        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] != hash.recover(signatures[i]))
                return SIG_VALIDATION_FAILED;
        }
        return 0;
    }

    function initialize(
        address[] memory initialOwners,
        uint256 numOfConfirmRequired,
        address[] memory gurdians,
        uint256 threshold
    ) public initializer {
        _initialize(initialOwners, numOfConfirmRequired, gurdians, threshold);
    }

    function _initialize(
        address[] memory _initialOwners,
        uint256 _numOfConfirmRequired,
        address[] memory _gurdians,
        uint256 _threshold
    ) internal {
        require(_initialOwners.length > 1, "owners not enough");
        require(
            _numOfConfirmRequired > 0 &&
                _numOfConfirmRequired <= _initialOwners.length,
            "number of confirm not sync with number of owners"
        );

        for (uint256 i = 0; i < _initialOwners.length; i++) {
            require(_initialOwners[i] != address(0), "invalid owner");
            owners.push(_initialOwners[i]);
        }

        for (uint256 i = 0; i < _gurdians.length; i++) {
            gurdians[i] = _gurdians[i];
            isGurdian[gurdians[i]] = true;
        }

        numOfConfirmRequired = _numOfConfirmRequired;

        threshold = _threshold;

        emit WalletInitialized(
            _entryPoint,
            _initialOwners,
            _numOfConfirmRequired,
            gurdians,
            threshold
        );
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                // The assembly code here skips the first 32 bytes of the result, which contains the length of data.
                // It then loads the actual error message using mload and calls revert with this error message.
                revert(add(result, 32), mload(result))
            }
        }
    }

    function executeBatch(
        Transaction[] memory txn
    ) external _requireCalledByEntryPointOrWalletFactory {
        for (uint256 i = 0; i < txn.length; i++) {
            _call(txn[i].to, txn[i].value, txn[i].data);
        }
    }

    function encodeSignatures(
        bytes memory signatures
    ) public pure returns (bytes memory) {
        return abi.encode(signatures);
    }

    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    receive() external payable {}

    /*
        Multisig functions
    */

    function submitTransaction(
        address[] calldata _to,
        uint256[] calldata _value,
        bytes[] calldata _data
    ) external {
        currentTransationNum++;
        for (uint256 i = 0; i < _to.length; i++) {
            require(_to[i] != addres(0), "Invalid target address");
            require(!inBlackList[_to], "target address is in black list");
            transactions[currentTransationNum].push(
                Transaction({
                    to: _to[i],
                    value: _value[i],
                    data: _data[i],
                    executed: false,
                    transactionId: currentTransationNum
                })
            );
        }
    }

    function confirmTransaction(address _transactionId) external {
        require(_transactionId < currentTransationNum, "Invalid transactionId");
        require(
            !isConfirmed[_transactionId][msg.sender],
            "already confirm transaction"
        );
        isConfirmed[_transactionId][msg.sender] = true;
        if (isTransactionConfirmedAlready(_transactionId)) {
            executeTransaction(_transactionId);
        }
    }

    function isTransactionConfirmedAlready(
        _transactionId
    ) internal view returns (bool) {
        require(
            _transactionId < currentTransationNum,
            "Invalid transaction Id"
        );
        uint256 confirmedNumForTransactionId;
        for (uint256 i = 0; i < owners.length; i++) {
            if (isConfirmed[_transactions][owners[i]]) {
                confirmedNumForTransactionId++;
            }
        }
        return confirmedNumForTransactionId >= numOfConfirmRequired;
    }

    function executeTransaction(
        address _transactionId
    ) external payable returns (bool) {
        require(
            _transactionId < currentTransationNum,
            "Invalid transaction Id"
        );
        require(
            !transactions[_transactionId].executed,
            "transaction has been executed"
        );
        transactions[_transactionId].executed = true;
        Transaction[] memory txn = transactions[_transactionId];
        executeBatch(txn);
    }

    function getTransactionInfo(
        uint _transactionId
    ) public view returns (Transaction[] memory) {
        require(_transactionId < transactions.length, "Invalid transaction Id");
        Transaction[] memory txn = transactions[_transactionId];
        return txn;
    }

    /*
    social recovery
    */

    function initialRecovery(
        address oldOwner,
        address newOwner
    ) external onlyGurdians notInRecovery {
        require(isOwners[oldOwner], "not in owner list");
        require(!isOwners[newOwner], "already in owner list");
        require(!isGurdian[newOwner], "cant not be the gurdians");
        require(!noLongerOwners[newOwner], "no longer the owner of the wallet");

        currentRecoveryRound++;
        executeRecoveryTimestamp[currentRecoveryRound] =
            block.timestamp +
            2 days;
        recoveryInfo[msg.sender] = Recovery(
            newOwner,
            currentRecoveryRound,
            false
        );

        isRecovery = true;
    }

    function supportRecovery(
        address oldOwner,
        address newOwner
    ) external onlyGurdians onlyInRecovery {
        require(isOwners[oldOwner], "not in owner list");
        require(!isOwners[newOwner], "already in owner list");
        require(!isGurdian[newOwner], "cant not be the gurdians");
        require(!noLongerOwners[newOwner], "no longer the owner of the wallet");
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
        address oldOwner,
        address newOwner,
        address[] calldata gurdiansList
    ) external onlyGurdians onlyInRecovery {
        require(
            block.timestamp > executeRecoveryTimestamp[currentRecoveryRound],
            "not the time to execute recovery"
        );
        require(
            gurdiansList.length >= threshold,
            "need more gurdians agree to execute recovery"
        );
        for (uint256 i = 0; i < gurdiansList.length; i++) {
            require(
                recoveryInfo[gurdiansList[i]].recoveryRound ==
                    currentRecoveryRound,
                "wrong recovery round"
            );
            require(
                recoveryInfo[gurdiansList[i]].newOwnerAddr == newOwner,
                "not support the newOwner"
            );
            require(
                !recoveryInfo[gurdiansList[i]].usedInExecuteRecovery,
                "duplicate gurdians in recovery"
            );

            recoveryInfo[gurdiansList[i]].usedInExecuteRecovery = true;
        }

        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == oldOwner) {
                isOwners[oldOwner] = false;
                owners[i] = newOwner;
                isOwners[newOwner] = true;
                noLongerOwners[oldOwner] = true;
            }
        }

        isRecovery = false;
    }

    function initiateGurdianRemoval(
        address gurdianToRemove
    ) external onlyOwners notInRecovery {
        require(isGurdian[gurdianToRemove], "not a gurdian");
        gurdianToRemovalTimestamp[gurdianToRemove] = block.timestamp + 3 days;
    }
}
