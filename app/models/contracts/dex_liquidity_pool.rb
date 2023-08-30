class Contracts::DexLiquidityPool < Contract
  dumbContract :public, :token0
  dumbContract :public, :token1
  
  constructor(token0: :dumbContract, token1: :dumbContract) do
    s.token0 = token0
    s.token1 = token1
  end
  
  function :add_liquidity, {token_0_amount: :uint256, token_1_amount: :uint256}, :public do
    DumbContract(s.token0).transferFrom(
      from: msg.sender,
      to: dumbContractId(this),
      amount: token_0_amount
    )
    
    DumbContract(s.token1).transferFrom(
      from: msg.sender,
      to: dumbContractId(this),
      amount: token_1_amount
    )
  end
  
  function :reserves, {}, :public, :view, returns: :string do
    json_data = {
      token0: DumbContract(s.token0).balanceOf(arg0: dumbContractId(this)),
      token1: DumbContract(s.token1).balanceOf(arg0: dumbContractId(this))
    }.to_json
    
    return "data:application/json,#{json_data}"
  end
  
  function :calculate_output_amount, {
    input_token: :dumbContract,
    output_token: :dumbContract,
    input_amount: :uint256
  }, :public, :view, returns: :uint256 do
    input_reserve = DumbContract(input_token).balanceOf(arg0: dumbContractId(this))
    output_reserve = DumbContract(output_token).balanceOf(arg0: dumbContractId(this))
    
    ((input_amount * output_reserve) / (input_reserve + input_amount)).to_i
  end
  
  function :swap, {
    input_token: :dumbContract,
    output_token: :dumbContract,
    input_amount: :uint256
  }, :public, returns: :uint256 do
    require([s.token0, s.token1].include?(input_token), "Invalid input token")
    require([s.token0, s.token1].include?(output_token), "Invalid output token")
    
    require(input_token != output_token, "Input and output tokens can't be the same")
    
    output_amount = calculate_output_amount(
      input_token: input_token,
      output_token: output_token,
      input_amount: input_amount
    )
    
    output_reserve = DumbContract(output_token).balanceOf(arg0: dumbContractId(this))
    
    require(output_amount <= output_reserve, "Insufficient output reserve")
  
    DumbContract(input_token).transferFrom(
      from: msg.sender,
      to: dumbContractId(this),
      amount: input_amount
    )
  
    DumbContract(output_token).transfer(
      to: msg.sender,
      amount: output_amount
    )
  
    return output_amount
  end
end
