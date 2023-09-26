class Contracts::UniswapSetupZap < ContractImplementation
  array :address, :public, :factories
  array :address, :public, :tokenAs
  array :address, :public, :tokenBs
  array :address, :public, :pairs
  array :address, :public, :routers
  
  string :public, :name
  
  event :ZapOneSetup, { factory: :address, tokenA: :address, tokenB: :address, pair: :address, router: :address }
  
  constructor() {
    s.name = 'UniswapSetupZap'
  }
  
  function :zapDumbSwap, { etherAddress: :address, admin: :address }, :public do
    ether = ERC20(etherAddress)
    etherBalance = ether.balanceOf(address(this))
    
    require(etherBalance > 10.ether, 'Not enough ether')
    
    factory = new UniswapV2Factory(_feeToSetter: address(this))
    factory.setFeeTo(admin)
    factory.setFeeToSetter(admin)
    
    router = new UniswapV2Router(
      _factory: factory,
      _WETH: address(0)
    )
    
    ether.approve(router, (2 ** 255))
    
    names = array(:string)
    symbols = array(:string)
    
    names.push("Chameleon")
    symbols.push("CHAM")
    
    names.push("Mirage")
    symbols.push("MIR")
    
    names.push("Emerald")
    symbols.push("EMD")
    
    names.push("Oasis")
    symbols.push("OAS")
        
    names.push("Paradox")
    symbols.push("PARA")
    
    names.push("Peridot")
    symbols.push("PERI")
    
    for i in 0...names.length
      supply = ((i + 1) * 2000).ether
      
      token = new PublicMintERC20(
        name: names[i],
        symbol: symbols[i],
        maxSupply: supply,
        perMintLimit: supply,
        decimals: 18
      )
      
      token.mint(amount: supply)
      token.approve(router, (2 ** 255))
      
      router.addLiquidity(
        tokenA: etherAddress,
        tokenB: token,
        amountADesired: etherBalance.div(names.length),
        amountBDesired: supply,
        amountAMin: 0,
        amountBMin: 0,
        to: admin,
        deadline: block.timestamp + 1000
      )
    end
    
    return nil
  end
  
  function :doZapOld, :public do
    factory = new UniswapV2Factory(_feeToSetter: msg.sender)
    
    tokenA = new UnsafeNoApprovalERC20(
      name: "TokenA (#{block.number})",
      symbol: "TKA",
    )
    
    tokenB = new UnsafeNoApprovalERC20(
      name: "TokenB (#{block.number})",
      symbol: "TKB",
    )
    
    router = new UniswapV2Router(
      _factory: factory,
      _WETH: address(this)
    )
    
    pair = factory.createPair(tokenA, tokenB)
    
    tokenA.airdrop(to: msg.sender, amount: 1e6.ether)
    tokenB.airdrop(to: msg.sender, amount: 1e6.ether)
    
    s.factories.push(factory)
    s.tokenAs.push(tokenA)
    s.tokenBs.push(tokenB)
    s.pairs.push(pair)
    s.routers.push(router)
    
    emit :ZapOneSetup, { factory: factory, tokenA: tokenA, tokenB: tokenB, pair: pair, router: router }
  end
  
  function :lastZap, :public, :view, returns: { factory: :address, tokenA: :address, tokenB: :address, pair: :address, router: :address } do
    return {
      factory: s.factories[s.factories.length - 1],
      tokenA: s.tokenAs[s.tokenAs.length - 1],
      tokenB: s.tokenBs[s.tokenBs.length - 1],
      pair: s.pairs[s.pairs.length - 1],
      router: s.routers[s.routers.length - 1]
    }
  end
  
  function :userStats, {
    user: :address,
    router: :address,
    factory: :address,
    tokenA: :address,
    tokenB: :address,
  }, :public, :view, returns: {
    userTokenABalance: :uint256,
    userTokenBBalance: :uint256,
    tokenAReserves: :uint256,
    tokenBReserves: :uint256,
    userLPBalance: :uint256
  } do
    tokenAReserves, tokenBReserves = UniswapV2Router(router).getReserves(factory, tokenA, tokenB)
    pair = UniswapV2Factory(factory).getPair(tokenA, tokenB)
    
    return {
      userTokenABalance: ERC20(tokenA).balanceOf(user),
      userTokenBBalance: ERC20(tokenB).balanceOf(user),
      tokenAReserves: tokenAReserves,
      tokenBReserves: tokenBReserves,
      userLPBalance: UniswapV2ERC20(pair).balanceOf(user)
    }
  end
end
