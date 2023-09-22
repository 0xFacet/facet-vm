class Contracts::OpenEditionERC721 < ContractImplementation
  is :ERC721
  
  string :public, :contentURI
  uint256 :public, :maxPerAddress
  uint256 :public, :totalSupply
  string :public, :description
  
  datetime :public, :mintStart
  datetime :public, :mintEnd
  
  constructor(
    name: :string,
    symbol: :string,
    contentURI: :string,
    maxPerAddress: :uint256,
    description: :string,
    mintStart: :datetime,
    mintEnd: :datetime
  ) {
    ERC721.constructor(name: name, symbol: symbol)
    
    s.maxPerAddress = maxPerAddress
    s.description = description
    s.contentURI = contentURI
    s.mintStart = mintStart
    s.mintEnd = mintEnd
  }
  
  function :mint, { amount: :uint256 }, :public, returns: :uint256 do
    require(amount > 0, 'Amount must be positive')
    require(amount + s._balanceOf[msg.sender] <= s.maxPerAddress, 'Exceeded mint limit')
    require(block.timestamp >= s.mintStart, 'Minting has not started')
    require(block.timestamp < s.mintEnd, 'Minting has ended')
    
    amount.times do |id|
      _mint(to: msg.sender, id: s.totalSupply + id)
    end
    
    s.totalSupply += amount
  end
  
  function :tokenURI, { id: :uint256 }, :public, :view, :override, returns: :string do
    require(_exists(id: id), 'ERC721Metadata: URI query for nonexistent token')

    json_data = {
      name: "#{s.name} ##{string(id)}",
      description: s.description,
      image: s.contentURI,
    }.to_json
    
    return "data:application/json,#{json_data}"
  end
end