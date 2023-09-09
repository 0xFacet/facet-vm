class Contracts::ERC20LiquidityPool < ContractImplementation
  address :public, :token0
  address :public, :token1
  
  constructor(token0: :address, token1: :address) do
    s.token0 = token0
    s.token1 = token1
  end
  
  function :addLiquidity, {token0Amount: :uint256, token1Amount: :uint256}, :public do
    DumbContract(s.token0).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: token0Amount
    )
    
    DumbContract(s.token1).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: token1Amount
    )
  end
  
  function :reserves, {}, :public, :view, returns: :string do
    jsonData = {
      token0: DumbContract(s.token0).balanceOf(address(this)),
      token1: DumbContract(s.token1).balanceOf(address(this))
    }.to_json
    
    return "data:application/json,#{jsonData}"
  end
  
  function :calculateOutputAmount, {
    inputToken: :address,
    outputToken: :address,
    inputAmount: :uint256
  }, :public, :view, returns: :uint256 do
    inputReserve = DumbContract(inputToken).balanceOf(address(this))
    outputReserve = DumbContract(outputToken).balanceOf(address(this))
    
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
    
    outputReserve = DumbContract(outputToken).balanceOf(address(this))
    
    require(outputAmount <= outputReserve, "Insufficient output reserve")
  
    DumbContract(inputToken).transferFrom(
      from: msg.sender,
      to: address(this),
      amount: inputAmount
    )
  
    DumbContract(outputToken).transfer(
      msg.sender,
      outputAmount
    )
  
    return outputAmount
  end
end
