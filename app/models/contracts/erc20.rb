class Contracts::ERC20 < Contract
  pragma :rubidity, "1.0.0"
  
  abstract
  
  event :Transfer, { from: :addressOrDumbContract, to: :addressOrDumbContract, amount: :uint256 }
  event :Approval, { owner: :addressOrDumbContract, spender: :addressOrDumbContract, amount: :uint256 }

  string :public, :name
  string :public, :symbol
  uint256 :public, :decimals
  
  uint256 :public, :totalSupply

  mapping ({ addressOrDumbContract: :uint256 }), :public, :balanceOf
  mapping ({ addressOrDumbContract: mapping(addressOrDumbContract: :uint256) }), :public, :allowance
  
  constructor(name: :string, symbol: :string, decimals: :uint256) {
    s.name = name
    s.symbol = symbol
    s.decimals = decimals
  }

  function :approve, { spender: :addressOrDumbContract, amount: :uint256 }, :public, :virtual, returns: :bool do
    s.allowance[msg.sender][spender] = amount
    
    emit :Approval, owner: msg.sender, spender: spender, amount: amount
    
    return true
  end
  
  function :transfer, { to: :addressOrDumbContract, amount: :uint256 }, :public, :virtual, returns: :bool do
    require(s.balanceOf[msg.sender] >= amount, 'Insufficient balance')
    
    s.balanceOf[msg.sender] -= amount
    s.balanceOf[to] += amount

    emit :Transfer, from: msg.sender, to: to, amount: amount
    
    return true
  end
  
  function :transferFrom, {
    from: :addressOrDumbContract,
    to: :addressOrDumbContract,
    amount: :uint256
  }, :public, :virtual, returns: :bool do
    allowed = s.allowance[from][msg.sender]
    
    s.allowance[from][msg.sender] = allowed - amount
    
    s.balanceOf[from] -= amount
    s.balanceOf[to] += amount
    
    emit :Transfer, from: from, to: to, amount: amount
    
    return true
  end
  
  function :_mint, { to: :addressOrDumbContract, amount: :uint256 }, :internal, :virtual do
    s.totalSupply += amount
    s.balanceOf[to] += amount
    
    emit :Transfer, from: address(0), to: to, amount: amount
  end
  
  function :_burn, { from: :addressOrDumbContract, amount: :uint256 }, :internal, :virtual do
    s.balanceOf[from] -= amount
    s.totalSupply -= amount
    
    emit :Transfer, from: from, to: address(0), amount: amount
  end
end
