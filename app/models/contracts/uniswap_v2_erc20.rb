class Contracts::UniswapV2ERC20 < ContractImplementation
  is :ERC20
  
  constructor() {
    ERC20.constructor(
      name: "ScribeSwap V2",
      symbol: "SCR",
      decimals: 18
    )
  }
end
