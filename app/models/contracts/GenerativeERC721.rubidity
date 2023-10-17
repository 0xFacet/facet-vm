pragma :rubidity, "1.0.0"

import './ERC721.rubidity'

contract :GenerativeERC721, is: :ERC721 do
  string :public, :generativeScript
  mapping ({ uint256: :uint256 }), :public, :tokenIdToSeed
  
  uint256 :public, :totalSupply
  uint256 :public, :maxSupply
  uint256 :public, :maxPerAddress
  string :public, :description
  
  constructor(
    name: :string,
    symbol: :string,
    generativeScript: :string,
    maxSupply: :uint256,
    description: :string,
    maxPerAddress: :uint256
  ) {
    ERC721.constructor(name: name, symbol: symbol)
    
    s.maxSupply = maxSupply
    s.maxPerAddress = maxPerAddress
    s.description = description
    s.generativeScript = generativeScript
  }
  
  function :mint, { amount: :uint256 }, :public, returns: :uint256 do
    require(amount > 0, 'Amount must be positive')
    require(amount + s._balanceOf[msg.sender] <= s.maxPerAddress, 'Exceeded mint limit')
    require(amount + s.totalSupply <= s.maxSupply, 'Exceeded max supply')
    
    hash = blockhash(block.number).cast(:uint256) % (2 ** 48)
    
    amount.times do |id|
      tokenId = s.totalSupply + id
      seed = hash + tokenId
      
      s.tokenIdToSeed[tokenId] = seed
      
      _mint(to: msg.sender, id: tokenId)
    end
    
    s.totalSupply += amount
  end
  
  function :tokenURI, { id: :uint256 }, :public, :view, :override, returns: :string do
    require(_exists(id: id), 'ERC721Metadata: URI query for nonexistent token')
    
    html = getHTML(seed: s.tokenIdToSeed[id])
    
    html_as_base_64_data_uri = "data:text/html;base64," + esc.base64Encode(html)
    
    json_data = {
      name: "#{s.name} ##{string(id)}",
      description: s.description,
      animation_url: html_as_base_64_data_uri,
    }.to_json
    
    return "data:application/json,#{json_data}"
  end
  
  function :getHTML, { seed: :uint256 }, :public, :view, returns: :string do
    <<~HTML
      <html>
        <head>
          <style>
            body,
            html {
              width: 100%;
              height: 100%;
              margin: 0;
              padding: 0;
              overflow: hidden;
              display: block;
            }

            #canvas {
              position: absolute;
            }
          </style>
        </head>
        <body>
          <canvas id="canvas"></canvas>
        </body>
        <script>
          window.SEED = #{string(seed)};
          #{s.generativeScript}
        </script>
      </html>
    HTML
  end
end
