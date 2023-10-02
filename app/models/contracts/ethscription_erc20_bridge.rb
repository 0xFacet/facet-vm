class Contracts::EthscriptionERC20Bridge < ContractImplementation
  pragma :rubidity, "1.0.0"
  
  is :ERC20

  event :InitiateWithdrawal, { from: :address, escrowedId: :bytes32, withdrawalId: :bytes32 }
  event :WithdrawalComplete, { to: :address, escrowedIds: [:bytes32], withdrawalIds: [:bytes32] }

  string :public, :ethscriptionsTicker
  uint256 :public, :ethscriptionMintAmount
  uint256 :public, :ethscriptionMaxSupply
  bytes32 :public, :ethscriptionDeployId
  
  address :public, :trustedSmartContract
  mapping ({ bytes32: :address }), :public, :pendingWithdrawalEthscriptionToOwner
  mapping ({ bytes32: :address }), :public, :bridgedEthscriptionToOwner
  mapping ({ address: array(:bytes32) }), :public, :pendingUserWithdrawalIds
  mapping ({ bytes32: :bytes32 }), :public, :withdrawalIdToEscrowedId
  
  constructor(
    name: :string,
    symbol: :string,
    trustedSmartContract: :address,
    ethscriptionDeployId: :bytes32
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
  
  function :bridgeIn, { to: :address, escrowedId: :bytes32 }, :public do
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

    maxId = s.ethscriptionMaxSupply.div(s.ethscriptionMintAmount)
    
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
  
  function :bridgeOut, { escrowedId: :bytes32 }, :public do
    require(s.bridgedEthscriptionToOwner[escrowedId] == msg.sender, "Ethscription not owned by sender")
    
    _burn(from: msg.sender, amount: s.ethscriptionMintAmount * (10 ** decimals))
    
    withdrawalId = TransactionContext.transaction_hash
    
    require(
      s.withdrawalIdToEscrowedId[withdrawalId] == TypedVariable.create(:bytes32),
      "Withdrawal already started"
    )

    s.bridgedEthscriptionToOwner[escrowedId] = address(0)
    s.pendingWithdrawalEthscriptionToOwner[escrowedId] = msg.sender
    s.pendingUserWithdrawalIds[msg.sender].push(withdrawalId)
    s.withdrawalIdToEscrowedId[withdrawalId] = escrowedId
    
    emit :InitiateWithdrawal, from: msg.sender, escrowedId: escrowedId, withdrawalId: withdrawalId
  end
  
  function :markWithdrawalComplete, {
    to: :address,
    withdrawalIds: [:bytes32]
  }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      'Only the trusted smart contract can mark withdrawals as complete'
    )
    
    for i in 0...withdrawalIds.length
      withdrawalId = withdrawalIds[i]
      escrowedId = withdrawalIdToEscrowedId[withdrawalId]

      require(
        s.pendingWithdrawalEthscriptionToOwner[escrowedId] == to,
        "Withdrawal not initiated"
      )
        
      require(
        _removeFirstOccurenceOfValueFromArray(
          s.pendingUserWithdrawalIds[to],
          withdrawalId
        ),
        "Withdrawal id not found"
      )
      
      s.pendingWithdrawalEthscriptionToOwner[escrowedId] = address(0)
      s.withdrawalIdToEscrowedId[withdrawalId] = TypedVariable.create(:bytes32)
    end
    
    emit :WithdrawalComplete, to: to, escrowedIds: escrowedIds, withdrawalIds: withdrawalIds
  end
  
  function :getPendingWithdrawalsForUser, { user: :address }, :public, :view, returns: [:bytes32] do
    return s.pendingUserWithdrawalIds[user]
  end
  
  function :_removeFirstOccurenceOfValueFromArray, { arr: array(:bytes32), value: :bytes32 }, :internal, returns: :bool do
    for i in 0...arr.length
      if arr[i] == value
        return _removeItemAtIndex(arr: arr, indexToRemove: i)
      end
    end
    
    return false
  end
  
  function :_removeItemAtIndex, { arr: array(:bytes32), indexToRemove: :uint256 }, :internal, returns: :bool do
    lastIndex = arr.length - 1
    
    if lastIndex != indexToRemove
      lastItem = arr[lastIndex]
      arr[indexToRemove] = lastItem
    end
    
    arr.pop
    
    return true
  end
end
