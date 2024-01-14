// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract TestERC721 is ERC721 {
    constructor() ERC721("TestERC721", "T721") {}

    function mint(address to, uint256 tokenId) public virtual {
        _mint(to, tokenId);
    }
}
