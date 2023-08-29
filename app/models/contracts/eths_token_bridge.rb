class Contracts::EthsTokenBridge < Contract
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
    ERC20(name: name, symbol: symbol, decimals: 18)
    
    s.trustedSmartContract = trustedSmartContract
  }
  
  function :bridgeIn, { to: :address, escrowedId: :ethscriptionId }, :public do
    require(
      address(msg.sender) == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    ethscription = esc.getEthscriptionById(escrowedId)
    uri = ethscription.contentUri
    
    id = uri[/data:,{"p":"erc-20","op":"mint","tick":"eths","id":"([1-9]+\d*)","amt":"1000"}/, 1]
    
    require(id.to_i > 0 && id.to_i <= 21000, "Invalid token id")
    require(ethscription.currentOwner == s.trustedSmartContract, "Ethscription not owned by recipient")
    require(ethscription.previousOwner == to, "Ethscription not owned by recipient")
    
    _mint(to: to, amount: 1000)
  end
  
  function :bridgeOut, { amount: :uint256 }, :public do
    require(amount % 1000 == 0, "Amount must be a multiple of 1000")
    
    _burn(from: msg.sender, amount: amount)
    
    s.pendingWithdrawals[address(msg.sender)] += amount
    
    emit :InitiateWithdrawal, from: address(msg.sender), amount: amount
  end
  
  function :markWithdrawalComplete, { to: :address, amount: :uint256 }, :public do
    require(
      address(msg.sender) == s.trustedSmartContract,
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
