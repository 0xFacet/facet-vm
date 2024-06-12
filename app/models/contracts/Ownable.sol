// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        owner = initialOwner;
    }

    function transferOwnership(address newOwner) public {
        require(msg.sender == owner, "msg.sender is not the owner");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function onlyOwner() internal view {
        require(msg.sender == owner, "msg.sender is not the owner");
    }
}
