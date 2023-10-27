pragma :rubidity, "1.0.0"

import "./ERC20.rubidity"
import "./Upgradeable.rubidity"

contract :EtherBridgeV2, is: [:ERC20, :Upgradeable], upgradeable: true do
  event :BridgedIn, { to: :address, amount: :uint256 }
  event :InitiateWithdrawal, { from: :address, amount: :uint256, withdrawalId: :bytes32 }
  event :WithdrawalComplete, { to: :address, amount: :uint256, withdrawalId: :bytes32 }
  
  address :public, :trustedSmartContract
  
  mapping ({ address: :uint256 }), :public, :pendingWithdrawalAmounts
  mapping ({ address: array(:bytes32) }), :public, :pendingUserWithdrawalIds
  
  mapping ({ bytes32: :uint256 }), :public, :withdrawalIdAmount
  mapping ({ address: :bytes32 }), :public, :userWithdrawalId
  
  constructor(
    name: :string,
    symbol: :string,
    trustedSmartContract: :address
  ) {
    require(trustedSmartContract != address(0), "Invalid smart contract")

    ERC20.constructor(name: name, symbol: symbol, decimals: 18)
    Upgradeable.constructor(upgradeAdmin: msg.sender)

    s.trustedSmartContract = trustedSmartContract
  }
  
  function :onUpgrade, { usersToProcess: [:address] }, :public do
    require(msg.sender == address(this), "Only the contract can call this function")
    
    for i in 0...usersToProcess.length
      user = usersToProcess[i]
      
      require(s.pendingUserWithdrawalIds[user].length == 1, "Migration not possible")
      
      withdrawalId = s.pendingUserWithdrawalIds[user].pop
      amount = s.pendingWithdrawalAmounts[user]

      s.pendingWithdrawalAmounts[user] = 0
      s.userWithdrawalId[user] = withdrawalId
      
      s.withdrawalIdAmount[withdrawalId] = amount
    end
    
    nil
  end
  
  function :bridgeIn, { to: :address, amount: :uint256 }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    _mint(to: to, amount: amount)
    emit :BridgedIn, to: to, amount: amount
  end
  
  function :bridgeOut, { amount: :uint256 }, :public do
    withdrawalId = esc.currentTransactionHash
    require(
      s.userWithdrawalId[msg.sender] == bytes32(0),
      "Withdrawal pending"
    )
    require(
      s.withdrawalIdAmount[withdrawalId] == 0,
      "Already bridged out"
    )

    s.userWithdrawalId[msg.sender] = withdrawalId
    s.withdrawalIdAmount[withdrawalId] = amount
      
    _burn(from: msg.sender, amount: amount)
    emit :InitiateWithdrawal, from: msg.sender, amount: amount, withdrawalId: withdrawalId
  end
  
  function :markWithdrawalComplete, {
    to: :address,
    withdrawalId: :bytes32
  }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      "Only the trusted smart contract can mark withdrawals as complete"
    )
    require(
      s.userWithdrawalId[to] == withdrawalId,
      "Withdrawal id not found"
    )
    
    amount = s.withdrawalIdAmount[withdrawalId]
    s.withdrawalIdAmount[withdrawalId] = 0
    s.userWithdrawalId[to] = bytes32(0)
      
    emit :WithdrawalComplete, to: to, amount: amount, withdrawalId: withdrawalId
  end
end
