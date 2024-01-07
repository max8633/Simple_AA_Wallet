// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Wallet} from "src/wallet.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "lib/openzeppelin-contracts/contracts/utils/Create2.sol";

contract WalletFactory {
    Wallet public immutable walletImplementation;

    constructor(IEntryPoint entryPoint) {
        walletImplementation = new Wallet(entryPoint, address(this));
    }

    function getAddress(
        address[] memory owners,
        uint256 numOfConfirmRequired,
        address[] memory gurdians,
        uint256 threshold,
        uint256 salt
    ) public view returns (address) {
        bytes memory walletInit = abi.encodeCall(
            Wallet.initialize,
            (owners, numOfConfirmRequired, gurdians, threshold)
        );
        bytes memory proxyConstructor = abi.encode(
            address(walletImplementation),
            walletInit
        );
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            proxyConstructor
        );
        bytes32 bytecodeHash = keccak256(bytecode);

        return Create2.computeAddress(bytes32(salt), bytecodeHash);
    }

    function createAccount(
        address[] memory owners,
        uint256 numOfConfirmRequired,
        address[] memory gurdians,
        uint256 threshold,
        uint256 salt
    ) external returns (Wallet) {
        address addr = getAddress(
            owners,
            numOfConfirmRequired,
            gurdians,
            threshold,
            salt
        );
        if (addr.code.length > 0) {
            return Wallet(payable(addr));
        } else {
            bytes memory walletInit = abi.encodeCall(
                Wallet.initialize,
                (owners, numOfConfirmRequired, gurdians, threshold)
            );
            ERC1967Proxy proxy = new ERC1967Proxy{salt: bytes32(salt)}(
                address(walletImplementation),
                walletInit
            );
            return Wallet(payable(address(proxy)));
        }
    }
}
