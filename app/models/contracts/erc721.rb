class Contracts::ERC721 < Contract
  pragma :rubidity, "1.0.0"

  abstract
  
  event :Transfer, { from: :addressOrDumbContract, to: :addressOrDumbContract, id: :uint256 }
  event :Approval, { owner: :addressOrDumbContract, spender: :addressOrDumbContract, id: :uint256 }
  event :ApprovalForAll, { owner: :addressOrDumbContract, operator: :addressOrDumbContract, approved: :bool }

  string :public, :name
  string :public, :symbol
  
  mapping ({ uint256: :addressOrDumbContract }), :internal, :_ownerOf
  mapping ({ addressOrDumbContract: :uint256 }), :internal, :_balanceOf
  
  mapping ({ uint256: :addressOrDumbContract }), :public, :getApproved
  mapping ({ addressOrDumbContract: mapping(addressOrDumbContract: :bool) }), :public, :isApprovedForAll

  constructor(name: :string, symbol: :string) {
    s.name = name
    s.symbol = symbol
  }
  
  function :ownerOf, { id: :uint256 }, :public, :view, :virtual, returns: :addressOrDumbContract do
    owner = s._ownerOf[id]
    require(owner != addressOrDumbContract(0), "ERC721: owner query for nonexistent token")
    
    return owner
  end
  
  function :balanceOf, { owner: :addressOrDumbContract }, :public, :view, :virtual, returns: :uint256 do
    require(owner != addressOrDumbContract(0), "ERC721: balance query for nonexistent owner")
    
    return s._balanceOf[owner]
  end
  
  function :approve, { spender: :addressOrDumbContract, id: :uint256 }, :public, :virtual do
    owner = s._ownerOf[id];
    
    require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");
    
    s.getApproved[id] = spender;

    emit :Approval, owner: owner, spender: spender, id: id
  end
  
  function :setApprovalForAll, { operator: :addressOrDumbContract, bool: :approved }, :public, :virtual do
    s.isApprovedForAll[msg.sender][operator] = approved;

    emit :ApprovalForAll, owner: msg.sender, operator: operator, approved: approved
  end
  
  function :transferFrom, { from: :addressOrDumbContract, to: :addressOrDumbContract, id: :uint256 }, :public, :virtual do
    require(from == s._ownerOf[id], "ERC721: transfer of token that is not own");
    require(to != addressOrDumbContract(0), "ERC721: transfer to the zero address");
    
    require(
      msg.sender == from ||
      s.getApproved[id] == msg.sender ||
      isApprovedForAll[from][msg.sender],
      "NOT_AUTHORIZED"
    );
    
    s._balanceOf[from] -= 1;
    s._balanceOf[to] += 1;
    
    _ownerOf[id] = to;
    
    s.getApproved[id] = addressOrDumbContract(0);
  end
  
  function :_exists, { id: :uint256 }, :internal, :virtual do
    return s._ownerOf[id] != addressOrDumbContract(0)
  end
  
  function :_mint, { to: :addressOrDumbContract, id: :uint256 }, :internal, :virtual do
    require(to != addressOrDumbContract(0), "ERC721: mint to the zero address");
    require(s._ownerOf[id] == addressOrDumbContract(0), "ERC721: token already minted");
    
    s._balanceOf[to] += 1;
    
    s._ownerOf[id] = to;
    
    emit :Transfer, from: addressOrDumbContract(0), to: to, id: id
  end
  
  function :_burn, { id: :uint256 }, :internal, :virtual do
    owner = s._ownerOf[id];
    
    require(owner != addressOrDumbContract(0), "ERC721: burn of nonexistent token");
    
    s._balanceOf[owner] -= 1;
    
    s._ownerOf[id] = addressOrDumbContract(0);
    
    s.getApproved[id] = addressOrDumbContract(0);
    
    emit :Transfer, from: owner, to: addressOrDumbContract(0), id: id
  end
  
  function :tokenURI, { id: :uint256 }, :public, :view, :virtual, returns: :string do
  end
end