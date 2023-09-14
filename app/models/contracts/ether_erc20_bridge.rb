class Contracts::EtherERC20Bridge < ContractImplementation
  pragma :rubidity, "1.0.0"
  
  is :ERC20

  event :InitiateWithdrawal, { from: :address, amount: :uint256 }
  event :WithdrawalComplete, { to: :address, amount: :uint256 }

  address :public, :trustedSmartContract
  mapping ({ address: :uint256 }), :public, :pendingWithdrawals
  
  constructor(
    name: :string,
    symbol: :string,
    trustedSmartContract: :address
  ) {
    ERC20.constructor(name: name, symbol: symbol, decimals: 18)
    
    s.trustedSmartContract = trustedSmartContract
  }
  
  function :bridgeIn, { to: :address, amount: :uint256 }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    _mint(to: to, amount: amount)
  end
  
  function :bridgeOut, { amount: :uint256 }, :public do
    _burn(from: msg.sender, amount: amount)
    
    s.pendingWithdrawals[msg.sender] += amount
    
    emit :InitiateWithdrawal, from: msg.sender, amount: amount
  end
  
  function :markWithdrawalComplete, { to: :address, amount: :uint256 }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      'Only the trusted smart contract can mark withdrawals as complete'
    )
    
    require(
      s.pendingWithdrawals[to] >= amount,
      'Insufficient pending withdrawal'
    )
    
    s.pendingWithdrawals[to] -= amount
    
    emit :WithdrawalComplete, to: to, amount: amount
  end
end
