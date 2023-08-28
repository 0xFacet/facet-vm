class Contracts::OpenEditionNft < Contract
  is :ERC721
  
  string :public, :contentURI
  uint256 :public, :maxPerAddress
  uint256 :public, :totalSupply
  string :public, :description
  
  constructor(
    name: :string,
    symbol: :string,
    contentURI: :string,
    maxPerAddress: :uint256,
    description: :string
  ) {
    ERC721(name: name, symbol: symbol)
    
    s.maxPerAddress = maxPerAddress
    s.description = description
    s.contentURI = contentURI
  }
  
  function :mint, { amount: :uint256 }, :public do
    require(amount > 0, 'Amount must be positive')
    require(amount + s._balanceOf[msg.sender] <= s.maxPerAddress, 'Exceeded mint limit')
    
    amount.times do |id|
      _mint(to: msg.sender, id: s.totalSupply + id)
    end
    
    s.totalSupply += amount
  end
  
  function :tokenURI, { id: :uint256 }, :public, :view, :override, returns: :string do
    {
      name: "#{s.name} ##{id.value}",
      description: s.description,
      image_data: s.contentURI,
    }.to_json
  end
end