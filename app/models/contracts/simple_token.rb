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
  ) do |a|
    s.name = a.name
    s.symbol = a.symbol
    s.maxSupply = a.maxSupply
    s.perMintLimit = a.perMintLimit
  end
  
  function :mint, { amount: :uint256 }, :public do |a|
    address = msg.sender
    
    require(a.amount > 0, 'Amount must be positive')
    require(a.amount <= s.perMintLimit, 'Exceeded mint limit')
    
    require(s.totalSupply + a.amount <= s.maxSupply, 'Exceeded max supply')

    s.totalSupply += a.amount
    s.balanceOf[address] += a.amount

    emit :transfer, from: address(0), to: address, value: a.amount
  end

  function :transfer, { to: :address, amount: :uint256 }, :public, :virtual do |a|
    from = msg.sender
    
    require(s.balanceOf[from] >= a.amount, 'Insufficient balance')
    
    s.balanceOf[from] -= a.amount
    s.balanceOf[a.to] += a.amount

    emit :transfer, from: from, to: a.to, value: a.amount
  end
  
  function :approve, { spender: :address, value: :uint256 }, :public, returns: :bool do |a|
    spender = a.spender.downcase
    value = a.value

    s.allowances[msg.sender][spender] = value
    
    emit :approval, owner: msg.sender, spender: spender, value: value
    
    return true
  end
end
