class Contracts::EthscriptionBridge < ContractImplementation
  pragma :rubidity, "1.0.0"
  
  is :ERC20

  event :InitiateWithdrawal, { from: :address, escrowedId: :ethscriptionId }
  event :WithdrawalComplete, { to: :address, escrowedId: :ethscriptionId }

  string :public, :ethscriptionsTicker
  uint256 :public, :ethscriptionMintAmount
  uint256 :public, :ethscriptionMaxSupply
  ethscriptionId :public, :ethscriptionDeployId
  
  address :public, :trustedSmartContract
  mapping ({ ethscriptionId: :address }), :public, :pendingWithdrawalEthscriptionToOwner
  mapping ({ ethscriptionId: :address }), :public, :bridgedEthscriptionToOwner
  
  constructor(
    name: :string,
    symbol: :string,
    trustedSmartContract: :address,
    ethscriptionDeployId: :ethscriptionId
  ) {
    ERC20.constructor(name: name, symbol: symbol, decimals: 18)
    
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
      msg.sender == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    require(
      s.bridgedEthscriptionToOwner[escrowedId] == address(0),
      "Ethscription already bridged in"
    )
    
    require(
      s.pendingWithdrawalEthscriptionToOwner[escrowedId] == address(0),
      "Ethscription withdrawal initiated"
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
    
    s.bridgedEthscriptionToOwner[escrowedId] = to
    _mint(to: to, amount: s.ethscriptionMintAmount * (10 ** decimals))
  end
  
  function :bridgeOut, { escrowedId: :ethscriptionId }, :public do
    require(s.bridgedEthscriptionToOwner[escrowedId] == msg.sender, "Ethscription not owned by sender")
    
    _burn(from: msg.sender, amount: s.ethscriptionMintAmount * (10 ** decimals))
    
    s.bridgedEthscriptionToOwner[escrowedId] = address(0)
    s.pendingWithdrawalEthscriptionToOwner[escrowedId] = msg.sender
    
    emit :InitiateWithdrawal, from: msg.sender, escrowedId: :ethscriptionId
  end
  
  function :markWithdrawalComplete, { to: :address, escrowedId: :ethscriptionId }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      'Only the trusted smart contract can mark withdrawals as complete'
    )
    
    require(
      s.pendingWithdrawalEthscriptionToOwner[escrowedId] == to,
      "Withdrawal not initiated"
    )
    
    s.pendingWithdrawalEthscriptionToOwner[escrowedId] = address(0)
    
    emit :WithdrawalComplete, to: to, escrowedId: :ethscriptionId
  end
end
