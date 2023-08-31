class Contracts::EthscriptionERC20Bridge < Contract
  pragma :rubidity, "1.0.0"
  
  is :ERC20

  event :InitiateWithdrawal, { from: :address, amount: :uint256 }
  event :WithdrawalComplete, { to: :address, amount: :uint256 }

  string :public, :ethscriptionsTicker
  uint256 :public, :ethscriptionMintAmount
  uint256 :public, :ethscriptionMaxSupply
  ethscriptionId :public, :ethscriptionDeployId
  
  address :public, :trustedSmartContract
  mapping ({ address: :uint256 }), :public, :pendingWithdrawals
  mapping ({ address: :uint256 }), :public, :ethscriptionsEscrowedCount
  
  constructor(
    name: :string,
    symbol: :string,
    trustedSmartContract: :address,
    ethscriptionDeployId: :ethscriptionId
  ) {
    ERC20(name: name, symbol: symbol, decimals: 18)
    
    s.trustedSmartContract = trustedSmartContract
    s.ethscriptionDeployId = ethscriptionDeployId
    
    deploy = esc.findEthscriptionById(ethscriptionDeployId)
    uri = deploy.contentUri
    parsed = JSON.parse(uri.split("data:,").last)
    
    require(parsed['op'] == 'deploy', "Invalid ethscription deploy id")
    require(parsed['p'] == 'erc-20', "Invalid protocol")
    
    s.ethscriptionsTicker = parsed['tick']
    s.ethscriptionMintAmount = parsed['lim']
    s.ethscriptionMaxSupply = parsed['max']
  }
  
  function :bridgeIn, { to: :address, escrowedId: :ethscriptionId }, :public do
    require(
      address(msg.sender) == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    ethscription = esc.findEthscriptionById(escrowedId)
    uri = ethscription.contentUri
    
    match_data = uri.match(/data:,{"p":"erc-20","op":"mint","tick":"([a-z]+)","id":"([1-9]+\d*)","amt":"([1-9]+\d*)"}/)
    
    require(match_data.present?, "Invalid ethscription content uri")
    
    tick, id, amt = match_data.captures
    
    tick = tick.cast(:string)
    id = id.cast(:uint256)
    amt = amt.cast(:uint256)
    
    require(tick == s.ethscriptionsTicker, "Invalid ethscription ticker")
    require(amt == s.ethscriptionMintAmount, "Invalid ethscription mint amount")

    maxId = s.ethscriptionMaxSupply / s.ethscriptionMintAmount
    
    require(id > 0 && id <= maxId, "Invalid token id")
    
    require(
      ethscription.currentOwner == s.trustedSmartContract,
      "Ethscription not owned by recipient. Observed owner: #{ethscription.currentOwner}, expected owner: #{s.trustedSmartContract}"
    )
    
    require(
      ethscription.previousOwner == to,
      "Ethscription not previously owned by to. Observed previous owner: #{ethscription.previousOwner}, expected previous owner: #{to}"
    )
    
    s.ethscriptionsEscrowedCount[to] += 1
    _mint(to: to, amount: s.ethscriptionMintAmount)
  end
  
  function :bridgeOut, { amount: :uint256 }, :public do
    require(amount % s.ethscriptionMintAmount == 0, "Amount must be a multiple of ethscriptionMintAmount")
    
    require(s.ethscriptionsEscrowedCount[address(msg.sender)] > 0, "No ethscriptions available to bridge out")
    require(s.balanceOf[msg.sender] >= amount, "No ethscriptions available to bridge out")
    
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
      "Insufficient pending withdrawal. Has: #{s.pendingWithdrawals[to]}, requested: #{amount}"
    )
    
    s.pendingWithdrawals[to] -= amount
    s.ethscriptionsEscrowedCount[to] -= amount / s.ethscriptionMintAmount
    
    emit :WithdrawalComplete, to: to, amount: amount
  end
end
