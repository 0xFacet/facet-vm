class Contracts::ERC20 < Contract
  pragma :rubidity, "1.0.0"
  
  event :transfer, { from: :addressOrDumbContract, to: :addressOrDumbContract, value: :uint256 }
  event :approval, { owner: :addressOrDumbContract, spender: :addressOrDumbContract, value: :uint256 }

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

  function :approve, { spender: :addressOrDumbContract, value: :uint256 }, :public, :virtual, returns: :bool do
    s.allowance[msg.sender][spender] = value
    
    emit :approval, owner: msg.sender, spender: spender, value: value
    
    return true
  end
  
  function :transfer, { to: :addressOrDumbContract, amount: :uint256 }, :public, :virtual, returns: :bool do
    require(s.balanceOf[msg.sender] >= amount, 'Insufficient balance')
    
    s.balanceOf[msg.sender] -= amount
    s.balanceOf[to] += amount

    emit :transfer, from: msg.sender, to: to, value: amount
    
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
    
    emit :transfer, from: from, to: to, value: amount
    
    return true
  end
  
  function :_mint, { to: :addressOrDumbContract, amount: :uint256 }, :internal, :virtual do
    s.totalSupply += amount
    s.balanceOf[to] += amount
    
    emit :transfer, from: address(0), to: to, value: amount
  end
  
  function :_burn, { from: :addressOrDumbContract, amount: :uint256 }, :internal, :virtual do
    s.balanceOf[from] -= amount
    s.totalSupply -= amount
    
    emit :transfer, from: from, to: address(0), value: amount
  end
end
