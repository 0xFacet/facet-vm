class Contracts::SimpleToken < Contract
  event :transfer, { from: :address, to: :address, value: :uint256 }
  event :approval, { owner: :address, spender: :address, value: :uint256 }
  
  string :public, :name
  string :public, :symbol
  
  uint256 :public, :maxSupply
  uint256 :public, :perMintLimit
  
  uint256 :public, :totalSupply
  
  mapping ({ address: :uint256 }), :public, :balanceOf
  mapping ({ address: mapping(address: :uint256) }), :public, :allowances
  
  constructor(
      name: :string,
      symbol: :string,
      maxSupply: :uint256,
      perMintLimit: :uint256
  ) do
    s.name = name
    s.symbol = symbol
    s.maxSupply = maxSupply
    s.perMintLimit = perMintLimit
  end
  
  function :mint, { amount: :uint256 }, :public do
    address = msg.sender
    
    require(amount > 0, 'Amount must be positive')
    require(amount <= s.perMintLimit, 'Exceeded mint limit')
    
    require(s.totalSupply + amount <= s.maxSupply, 'Exceeded max supply')

    s.totalSupply += amount
    s.balanceOf[address] += amount

    emit :transfer, from: address(0), to: address, value: amount
  end

  function :transfer, { to: :address, amount: :uint256 }, :public, :virtual do
    from = msg.sender
    
    require(s.balanceOf[from] >= amount, 'Insufficient balance')
    
    s.balanceOf[from] -= amount
    s.balanceOf[to] += amount

    emit :transfer, from: from, to: to, value: amount
  end
  
  function :approve, { spender: :address, value: :uint256 }, :public, returns: :bool do
    spender = spender.downcase
    value = value

    s.allowances[msg.sender][spender] = value
    
    emit :approval, owner: msg.sender, spender: spender, value: value
    
    return true
  end
end
