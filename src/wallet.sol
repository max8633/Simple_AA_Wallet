// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {BaseAccount} from "lib/account-abstraction/contracts/core/BaseAccount.sol";
import {UserOperation} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";


contract wallet is BaseAccount, Initializable{
    using ECDSA for bytes32;

    address[] public owners;

    address public immutable walletFactory;
    IEntryPoint private immutable _entryPoint;

    event WalletInitialized(IEntryPoint indexed entryPoint, address[] owners);
    constructor(IEntryPoint myEntryPoint, address myWalletFactory_){
        _entryPoint = myEntryPoint;
        walletFactory = myWalletFactory_;
    }

    function entryPoint() public view override returns (IEntryPoint){
        return _entryPoint;
    }

    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash) internal view override returns(uint256){
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        bytes[] memory signatures = abi.decode(userOp.signature, (bytes[]));

        for(uint256 i = 0, i < owners.length, i++){
            if(owners[i] != hash.recover(signatures[i]))
                return SIG_VALIDATION_FAILED;
        }
        return 0;
    }

    function initialize(address[] memory initialOwners) public initializer{
        _initialize(initialOwners);
    } 

    function _initialize(address[] memory initialOwners) internal{
        require(initialOwners.length > 0, "there is no initial owner");
        owners = initialOwners;
        emit WalletInitialized(_entryPoint, initialOwners);
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

}