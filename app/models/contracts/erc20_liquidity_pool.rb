class Contracts::ERC20LiquidityPool < ContractImplementation
  address :public, :token0
  address :public, :token1
  
  constructor(token0: :address, token1: :address) do
    s.token0 = token0
    s.token1 = token1
  end
  
  function :addLiquidity, {token0Amount: :uint256, token1Amount: :uint256}, :public do
    ERC20(s.token0).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: token0Amount
    )
    
    ERC20(s.token1).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: token1Amount
    )
  end
  
  function :reserves, {}, :public, :view, returns: { token0: :uint256, token1: :uint256 } do
    return {
      token0: ERC20(s.token0).balanceOf(address(this)),
      token1: ERC20(s.token1).balanceOf(address(this))
    }
  end
  
  function :calculateOutputAmount, {
    inputToken: :address,
    outputToken: :address,
    inputAmount: :uint256
  }, :public, :view, returns: :uint256 do
    inputReserve = ERC20(inputToken).balanceOf(address(this))
    outputReserve = ERC20(outputToken).balanceOf(address(this))
    
    ((inputAmount * outputReserve) / (inputReserve + inputAmount)).to_i
  end
  
  function :swap, {
    inputToken: :address,
    outputToken: :address,
    inputAmount: :uint256
  }, :public, returns: :uint256 do
    require([s.token0, s.token1].include?(inputToken), "Invalid input token")
    require([s.token0, s.token1].include?(outputToken), "Invalid output token")
    
    require(inputToken != outputToken, "Input and output tokens can't be the same")
    
    outputAmount = calculateOutputAmount(
      inputToken: inputToken,
      outputToken: outputToken,
      inputAmount: inputAmount
    )
    
    outputReserve = ERC20(outputToken).balanceOf(address(this))
    
    require(outputAmount <= outputReserve, "Insufficient output reserve")
  
    ERC20(inputToken).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: inputAmount
    )
  
    ERC20(outputToken).transfer(
      msg.sender,
      outputAmount
    )
  
    return outputAmount
  end
end
