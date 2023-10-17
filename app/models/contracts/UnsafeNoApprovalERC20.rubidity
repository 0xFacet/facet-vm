pragma :rubidity, "1.0.0"

import './ERC20.rubidity'

contract :UnsafeNoApprovalERC20, is: :ERC20 do
  constructor(
    name: :string,
    symbol: :string,
  ) {
    ERC20.constructor(name: name, symbol: symbol, decimals: 18)
  }
  
  function :mint, { amount: :uint256 }, :public do
    require(amount > 0, 'Amount must be positive')
    
    _mint(to: msg.sender, amount: amount)
  end
  
  function :airdrop, { to: :address, amount: :uint256 }, :public do
    require(amount > 0, 'Amount must be positive')
    
    _mint(to: to, amount: amount)
  end
  
  function :transferFrom, {
    from: :address,
    to: :address,
    amount: :uint256
  }, :public, :override, returns: :bool do
    require(s.balanceOf[from] >= amount, 'Insufficient balance')
    
    s.balanceOf[from] -= amount
    s.balanceOf[to] += amount
    
    emit :Transfer, from: from, to: to, amount: amount
    
    return true
  end
end
