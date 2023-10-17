pragma :rubidity, "1.0.0"

contract :ERC721, abstract: true do
  event :Transfer, { from: :address, to: :address, id: :uint256 }
  event :Approval, { owner: :address, spender: :address, id: :uint256 }
  event :ApprovalForAll, { owner: :address, operator: :address, approved: :bool }

  string :public, :name
  string :public, :symbol
  
  mapping ({ uint256: :address }), :internal, :_ownerOf
  mapping ({ address: :uint256 }), :internal, :_balanceOf
  
  mapping ({ uint256: :address }), :public, :getApproved
  mapping ({ address: mapping(address: :bool) }), :public, :isApprovedForAll

  constructor(name: :string, symbol: :string) {
    s.name = name
    s.symbol = symbol
  }
  
  function :ownerOf, { id: :uint256 }, :public, :view, :virtual, returns: :address do
    owner = s._ownerOf[id]
    require(owner != address(0), "ERC721: owner query for nonexistent token")
    
    return owner
  end
  
  function :balanceOf, { owner: :address }, :public, :view, :virtual, returns: :uint256 do
    require(owner != address(0), "ERC721: balance query for nonexistent owner")
    
    return s._balanceOf[owner]
  end
  
  function :approve, { spender: :address, id: :uint256 }, :public, :virtual do
    owner = s._ownerOf[id];
    
    require(msg.sender == owner || s.isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");
    
    s.getApproved[id] = spender;

    emit :Approval, owner: owner, spender: spender, id: id
  end
  
  function :setApprovalForAll, { operator: :address, bool: :approved }, :public, :virtual do
    s.isApprovedForAll[msg.sender][operator] = approved;

    emit :ApprovalForAll, owner: msg.sender, operator: operator, approved: approved
  end
  
  function :transferFrom, { from: :address, to: :address, id: :uint256 }, :public, :virtual do
    require(from == s._ownerOf[id], "ERC721: transfer of token that is not own");
    require(to != address(0), "ERC721: transfer to the zero address");
    
    require(
      msg.sender == from ||
      s.getApproved[id] == msg.sender ||
      isApprovedForAll[from][msg.sender],
      "NOT_AUTHORIZED"
    );
    
    s._balanceOf[from] -= 1;
    s._balanceOf[to] += 1;
    
    s._ownerOf[id] = to;
    
    s.getApproved[id] = address(0);
    
    return nil
  end
  
  function :_exists, { id: :uint256 }, :internal, :virtual, returns: :bool do
    return s._ownerOf[id] != address(0)
  end
  
  function :_mint, { to: :address, id: :uint256 }, :internal, :virtual do
    require(to != address(0), "ERC721: mint to the zero address");
    require(s._ownerOf[id] == address(0), "ERC721: token already minted");
    
    s._balanceOf[to] += 1;
    
    s._ownerOf[id] = to;
    
    emit :Transfer, from: address(0), to: to, id: id
  end
  
  function :_burn, { id: :uint256 }, :internal, :virtual do
    owner = s._ownerOf[id];
    
    require(owner != address(0), "ERC721: burn of nonexistent token");
    
    s._balanceOf[owner] -= 1;
    
    s._ownerOf[id] = address(0);
    
    s.getApproved[id] = address(0);
    
    emit :Transfer, from: owner, to: address(0), id: id
  end
  
  function :tokenURI, { id: :uint256 }, :public, :view, :virtual, returns: :string do
  end
end
