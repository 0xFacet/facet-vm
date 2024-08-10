// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

abstract contract ERC20 {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        
        emit Approval(msg.sender, spender, amount);
        
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
        
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowed >= amount, "Insufficient allowance");
        
        allowance[from][msg.sender] = allowed - amount;
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        
        emit Transfer(from, to, amount);
        
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        balanceOf[to] += amount;
        
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        require(balanceOf[from] >= amount, "Insufficient balance");
        
        balanceOf[from] -= amount;
        totalSupply -= amount;
        
        emit Transfer(from, address(0), amount);
    }
}

contract MyToken is ERC20 {
    constructor(address initialOwner)
        ERC20("MyToken", "MTK", 18)
    {}
    
    function mint(address to, uint256 amount) public {
        if (to == msg.sender) {
            _mint(to, amount);
        } else {
            _mint(address(0), amount);
        }
    }
}

// abstract contract Ownable {
//     address private _owner;

//     /**
//      * @dev The caller account is not authorized to perform an operation.
//      */
//     error OwnableUnauthorizedAccount(address account);

//     /**
//      * @dev The owner is not a valid owner account. (eg. `address(0)`)
//      */
//     error OwnableInvalidOwner(address owner);

//     event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

//     /**
//      * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
//      */
//     constructor(address initialOwner) {
//         if (initialOwner == address(0)) {
//             revert OwnableInvalidOwner(address(0));
//         }
//         _transferOwnership(initialOwner);
//     }

//     /**
//      * @dev Throws if called by any account other than the owner.
//      */
//     modifier onlyOwner() {
//         _checkOwner();
//         _;
//     }

//     /**
//      * @dev Returns the address of the current owner.
//      */
//     function owner() public view virtual returns (address) {
//         return _owner;
//     }

//     /**
//      * @dev Throws if the sender is not the owner.
//      */
//     function _checkOwner() internal view virtual {
//         if (owner() != msg.sender) {
//             revert OwnableUnauthorizedAccount(msg.sender);
//         }
//     }

//     /**
//      * @dev Leaves the contract without owner. It will not be possible to call
//      * `onlyOwner` functions. Can only be called by the current owner.
//      *
//      * NOTE: Renouncing ownership will leave the contract without an owner,
//      * thereby disabling any functionality that is only available to the owner.
//      */
//     function renounceOwnership() public virtual onlyOwner {
//         _transferOwnership(address(0));
//     }

//     /**
//      * @dev Transfers ownership of the contract to a new account (`newOwner`).
//      * Can only be called by the current owner.
//      */
//     function transferOwnership(address newOwner) public virtual onlyOwner {
//         if (newOwner == address(0)) {
//             revert OwnableInvalidOwner(address(0));
//         }
//         _transferOwnership(newOwner);
//     }

//     /**
//      * @dev Transfers ownership of the contract to a new account (`newOwner`).
//      * Internal function without access restriction.
//      */
//     function _transferOwnership(address newOwner) internal virtual {
//         address oldOwner = _owner;
//         _owner = newOwner;
//         emit OwnershipTransferred(oldOwner, newOwner);
//     }
// }
// contract MyToken is ERC20, Ownable {
//     constructor(address initialOwner)
//         ERC20("MyToken", "MTK", 18)
//         Ownable(initialOwner)
//     {}
    
//     function mint(address to, uint256 amount) public onlyOwner {
//         _mint(to, amount);
//     }
// }