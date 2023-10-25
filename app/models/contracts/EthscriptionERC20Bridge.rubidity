pragma :rubidity, "1.0.0"

import "./ERC20.rubidity"

contract :EthscriptionERC20Bridge, is: :ERC20 do
  event :BridgedIn, { to: :address, amount: :uint256 }
  event :InitiateWithdrawal, { from: :address, amount: :uint256, withdrawalId: :bytes32 }
  event :WithdrawalComplete, { to: :address, amount: :uint256, withdrawalId: :bytes32 }
  
  uint256 :public, :mintAmount
  address :public, :trustedSmartContract

  mapping ({ address: :uint256 }), :public, :bridgedInAmount
  mapping ({ bytes32: :uint256 }), :public, :withdrawalIdAmount
  mapping ({ address: :bytes32 }), :public, :userWithdrawalId
  
  constructor(
    name: :string,
    symbol: :string,
    mintAmount: :uint256,
    trustedSmartContract: :address
  ) {
    require(mintAmount > 0, "Invalid mint amount")
    require(trustedSmartContract != address(0), "Invalid smart contract")

    ERC20.constructor(name: name, symbol: symbol, decimals: 18)

    s.mintAmount = mintAmount
    s.trustedSmartContract = trustedSmartContract
  }
  
  function :bridgeIn, { to: :address, amount: :uint256 }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    s.bridgedInAmount[to] += amount

    _mint(to: to, amount: amount * s.mintAmount * 1.ether)
    emit :BridgedIn, to: to, amount: amount * s.mintAmount * 1.ether
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
    require(
      s.bridgedInAmount[msg.sender] >= amount,
      "Not enough bridged in"
    )

    s.userWithdrawalId[msg.sender] = withdrawalId
    s.withdrawalIdAmount[withdrawalId] = amount
    s.bridgedInAmount[msg.sender] -= amount
      
    _burn(from: msg.sender, amount: amount * s.mintAmount * 1.ether)
    emit :InitiateWithdrawal, from: msg.sender, amount: amount * s.mintAmount * 1.ether, withdrawalId: withdrawalId
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
      
    emit :WithdrawalComplete, to: to, amount: amount * s.mintAmount * 1.ether, withdrawalId: withdrawalId
  end
end
