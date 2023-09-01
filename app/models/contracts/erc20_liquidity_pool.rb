class Contracts::ERC20LiquidityPool < ContractImplementation
  dumbContract :public, :token0
  dumbContract :public, :token1
  
  constructor(token0: :dumbContract, token1: :dumbContract) do
    s.token0 = token0
    s.token1 = token1
  end
  
  function :addLiquidity, {token0Amount: :uint256, token1Amount: :uint256}, :public do
    DumbContract(s.token0).transferFrom(
      from: msg.sender,
      to: dumbContractId(this),
      amount: token0Amount
    )
    
    DumbContract(s.token1).transferFrom(
      from: msg.sender,
      to: dumbContractId(this),
      amount: token1Amount
    )
  end
  
  function :reserves, {}, :public, :view, returns: :string do
    jsonData = {
      token0: DumbContract(s.token0).balanceOf(arg0: dumbContractId(this)),
      token1: DumbContract(s.token1).balanceOf(arg0: dumbContractId(this))
    }.to_json
    
    return "data:application/json,#{jsonData}"
  end
  
  function :calculateOutputAmount, {
    inputToken: :dumbContract,
    outputToken: :dumbContract,
    inputAmount: :uint256
  }, :public, :view, returns: :uint256 do
    inputReserve = DumbContract(inputToken).balanceOf(arg0: dumbContractId(this))
    outputReserve = DumbContract(outputToken).balanceOf(arg0: dumbContractId(this))
    
    ((inputAmount * outputReserve) / (inputReserve + inputAmount)).to_i
  end
  
  function :swap, {
    inputToken: :dumbContract,
    outputToken: :dumbContract,
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
    
    outputReserve = DumbContract(outputToken).balanceOf(arg0: dumbContractId(this))
    
    require(outputAmount <= outputReserve, "Insufficient output reserve")
  
    DumbContract(inputToken).transferFrom(
      from: msg.sender,
      to: dumbContractId(this),
      amount: inputAmount
    )
  
    DumbContract(outputToken).transfer(
      to: msg.sender,
      amount: outputAmount
    )
  
    return outputAmount
  end
end
