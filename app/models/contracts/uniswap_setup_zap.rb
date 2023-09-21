class Contracts::UniswapSetupZap < ContractImplementation
  array :address, :public, :factories
  array :address, :public, :tokenAs
  array :address, :public, :tokenBs
  array :address, :public, :pairs
  array :address, :public, :routers
  
  event :ZapOneSetup, { factory: :address, tokenA: :address, tokenB: :address, pair: :address, router: :address }
  
  constructor() {}
  
  function :doZap, {}, :public do
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
  
  function :lastZap, {}, :public, :view, returns: { factory: :address, tokenA: :address, tokenB: :address, pair: :address, router: :address } do
    return {
      factory: s.factories[s.factories.length - 1],
      tokenA: s.tokenAs[s.tokenAs.length - 1],
      tokenB: s.tokenBs[s.tokenBs.length - 1],
      pair: s.pairs[s.pairs.length - 1],
      router: s.routers[s.routers.length - 1]
    }
  end
end
