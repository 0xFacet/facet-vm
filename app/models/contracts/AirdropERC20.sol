// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Ownable.sol';
import './ERC20.sol';

contract AirdropERC20 is ERC20, Ownable {
    uint256 public maxSupply;
    uint256 public perMintLimit;
    uint256 public singleTxAirdropLimit;

    constructor(
        string memory name,
        string memory symbol,
        address owner,
        uint256 maxSupply_,
        uint256 perMintLimit_,
        uint8 decimals_
    ) ERC20(name, symbol, decimals_) Ownable(owner) {
        maxSupply = maxSupply_;
        perMintLimit = perMintLimit_;
        singleTxAirdropLimit = 10;
    }

    function airdrop(address to, uint256 amount) public {
        onlyOwner();
      
        require(amount > 0, "Amount must be positive");
        require(amount <= perMintLimit, "Exceeded mint limit");
        require(totalSupply + amount <= maxSupply, "Exceeded max supply");
        
        _mint(to, amount);
    }

    function airdropMultiple(address[] memory addresses, uint256[] memory amounts) public {
        onlyOwner();
        
        require(addresses.length == amounts.length, "Address and amount arrays must be the same length");
        require(addresses.length <= singleTxAirdropLimit, "Cannot airdrop more than 10 addresses at a time");

        for (uint256 i = 0; i < addresses.length; i++) {
            airdrop(addresses[i], amounts[i]);
        }
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}