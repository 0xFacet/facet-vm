class Contracts::UniswapSetupZapOne < ContractImplementation
  event :ZapOneSetup, { factory: :address, tokenA: :address, tokenB: :address, pair: :address, router: :address }

  constructor() {
    factory = new UniswapV2Factory(_feeToSetter: msg.sender)
    
    tokenA = new PublicMintERC20(
      name: "TokenA (#{block.number})",
      symbol: "TKA",
      maxSupply: 21e6.ether,
      perMintLimit: 21e6.ether,
      decimals: 18
    )
    
    tokenB = new PublicMintERC20(
      name: "TokenB (#{block.number})",
      symbol: "TKB",
      maxSupply: 21e6.ether,
      perMintLimit: 21e6.ether,
      decimals: 18
    )
    
    router = new UniswapV2Router(
      _factory: factory,
      _WETH: address(this)
    )
    
    pair = factory.createPair(tokenA, tokenB)
    
    tokenA.airdrop(to: msg.sender, amount: 1e6.ether)
    tokenB.airdrop(to: msg.sender, amount: 1e6.ether)
    
    emit :ZapOneSetup, { factory: factory, tokenA: tokenA, tokenB: tokenB, pair: pair, router: router }
  }
end
