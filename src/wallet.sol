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

    //@notice store owners address
    address[] public owners;

    //@notice store wallet factory address in immutable variable
    address public immutable walletFactory;

    //@notice store entrypoint address in immutable variable
    IEntryPoint private immutable _entryPoint;

    //@notice store the least num need to confirm
    uint256 public numOfConfirmRequired;

    //@notice stor the info of transaction
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

    //@notice check if a transaction is confirmed by owners' address
    mapping(uint256 => mapping(address => bool)) isConfirmed;

    //@notcie check if the target address is in black list or not
    mapping(address => bool) inBlackList;

    //@notice store current transaction num
    uint256 public currentTransationNum;

    //@notice store the transactions
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

    //@notice store the time stamp when gurdian removal process is initiate
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

    //@notice only when msg.sender is entrypoint or wallet factory can call that functions
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
    ) external onlyOwners {
        currentTransationNum++;
        for (uint256 i = 0; i < _to.length; i++) {
            require(_to[i] != address(0), "Invalid target address");
            require(!inBlackList[_to[i]], "target address is in black list");
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

    function confirmTransaction(uint256 _transactionId) external onlyOwners {
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
        uint256 _transactionId
    ) internal view returns (bool) {
        require(
            _transactionId < currentTransationNum,
            "Invalid transaction Id"
        );
        uint256 confirmedNumForTransactionId;
        for (uint256 i = 0; i < owners.length; i++) {
            if (isConfirmed[_transactionId][owners[i]]) {
                confirmedNumForTransactionId++;
            }
        }
        return confirmedNumForTransactionId >= numOfConfirmRequired;
    }

    function executeTransaction(uint256 _transactionId) internal onlyOwners {
        require(
            _transactionId < currentTransationNum,
            "Invalid transaction Id"
        );
        Transaction[] memory txn = transactions[_transactionId];
        for (uint256 i = 0; i < txn.length; i++) {
            require(!txn[i].executed, "transaction has been executed");
            txn[i].executed = true;
        }
        execute(txn);
    }

    function execute(
        Transaction[] memory txn
    ) internal _requireCalledByEntryPointOrWalletFactory {
        for (uint256 i = 0; i < txn.length; i++) {
            _call(txn[i].to, txn[i].value, txn[i].data);
        }
    }

    function getTransactionInfo(
        uint256 _transactionId
    ) public view returns (Transaction[] memory) {
        require(
            _transactionId < currentTransationNum,
            "Invalid transaction Id"
        );
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

    bool public inGurdianUpdate;
    mapping(address => bool) gurdianUpdate;
    mapping(address => bool) isSupport;

    modifier notInGurdianUpdate() {
        require(!inGurdianUpdate, "one gurdian is in update mode now");
        _;
    }

    function initiateGurdianRemoval(
        address gurdianToRemoval
    ) external onlyOwners notInRecovery notInGurdianUpdate {
        require(gurdians.length - 1 >= threshold, "beyond threshold");
        require(
            gurdianToRemoval != address(0),
            "Invalid gurdian address to be removed"
        );
        require(
            !gurdianUpdate[gurdianToRemoval],
            "can update one gurdian at the same time"
        );
        require(isGurdian[gurdianToRemoval], "not a gurdian");
        require(!isOwners[gurdianToRemoval], "owner cant not be gurdian");
        gurdianToRemovalTimestamp[gurdianToRemoval] = block.timestamp + 3 days;
        gurdianUpdate[gurdianToRemoval] = true;
        inGurdianUpdate = true;
    }

    function supportGurdianRemoval(
        address gurdianToRemoval
    ) external onlyOwners notInRecovery {
        require(
            gurdianUpdate[gurdianToRemoval],
            "the gurdian you supported is not in update mode"
        );
        isSupport[msg.sender] = true;

        uint256 supportToGurdianRemoval;
        for (uint256 i = 0; i < owners.length; i++) {
            if (isSupport[owners[i]]) {
                supportToGurdianRemoval++;
            }
        }
        if (
            supportToGurdianRemoval == owners.length &&
            block.timestamp >= gurdianToRemovalTimestamp[gurdianToRemoval]
        ) {
            executeGurdianRemoval(gurdianToRemoval);
        }
    }

    function executeGurdianRemoval(address gurdianToRemoval) internal {
        isGurdian[gurdianToRemoval] = false;
        for (uint256 i = 0; i < gurdians.length; i++) {
            if (gurdians[i] == gurdianToRemoval) {
                gurdians[i] = gurdians[gurdians.length - 1];
                gurdians.pop();
            }
        }
    }
}
