class Contracts::UniswapV2Callee < ContractImplementation
  abstract
  
  function :uniswapV2Call, {
    sender: :address,
    amount0: :uint256,
    amount1: :uint256,
    data: :bytes
  }, :virtual, :external do
  end
end
