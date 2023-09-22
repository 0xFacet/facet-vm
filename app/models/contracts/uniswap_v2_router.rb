class Contracts::UniswapV2Router < ContractImplementation
  address :public, :factory
  address :public, :WETH
  
  constructor(_factory: :address, _WETH: :address) {
    s.factory = _factory
    s.WETH = _WETH
  }
  
  function :_addLiquidity, {
    tokenA: :address,
    tokenB: :address,
    amountADesired: :uint256,
    amountBDesired: :uint256,
    amountAMin: :uint256,
    amountBMin: :uint256
  }, :internal, :virtual, returns: { amountA: :uint256, amountB: :uint256 } do
    if UniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)
      UniswapV2Factory(factory).createPair(tokenA, tokenB)
    end
    
    reserveA, reserveB = getReserves(s.factory, tokenA, tokenB)
    
    if reserveA == 0 && reserveB == 0
      return { amountA: amountADesired, amountB: amountBDesired }
    else
      amountBOptimal = quote(amountADesired, reserveA, reserveB)
      
      if amountBOptimal <= amountBDesired
        require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT')
        
        return { amountA: amountADesired, amountB: amountBOptimal }
      else
        amountAOptimal = quote(amountBDesired, reserveB, reserveA)
        
        require(amountAOptimal <= amountADesired, "ASSERT")
        
        require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT')
        
        return { amountA: amountAOptimal, amountB: amountBDesired }
      end
    end
  end
  
  function :addLiquidity, {
    tokenA: :address,
    tokenB: :address,
    amountADesired: :uint256,
    amountBDesired: :uint256,
    amountAMin: :uint256,
    amountBMin: :uint256,
    to: :address,
    deadline: :uint256
  }, :public, :virtual, returns: { amountA: :uint256, amountB: :uint256, liquidity: :uint256 } do
    require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
    
    amountA, amountB = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin)
    
    pair = pairFor(s.factory, tokenA, tokenB)
    
    _safeTransferFrom(token: tokenA, from: msg.sender, to: pair, value: amountA)
    _safeTransferFrom(token: tokenB, from: msg.sender, to: pair, value: amountB)
    
    liquidity = UniswapV2Pair(pair).mint(to: to)
    
    return { amountA: amountA, amountB: amountB, liquidity: liquidity }
  end
  
  function :removeLiquidity, {
    tokenA: :address,
    tokenB: :address,
    liquidity: :uint256,
    amountAMin: :uint256,
    amountBMin: :uint256,
    to: :address,
    deadline: :uint256
  }, :public, :virtual, returns: { amountA: :uint256, amountB: :uint256 } do
    require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
    
    pair = pairFor(s.factory, tokenA, tokenB)
    UniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity)
    
    amount0, amount1 = UniswapV2Pair(pair).burn(to)
    
    token0, _ = sortTokens(tokenA, tokenB)

    (amountA, amountB) = tokenA == token0 ? [amount0, amount1] : [amount1, amount0]
    
    require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT')
    require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT')
    
    return { amountA: amountA, amountB: amountB }
  end
  
  function :swapExactTokensForTokens, { 
    amountIn: :uint256, 
    amountOutMin: :uint256, 
    path: [:address],
    to: :address, 
    deadline: :uint256 
  }, :public, :virtual, returns: [:uint256] do
    require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');

    amounts = getAmountsOut(factory, amountIn, path)
    
    require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT')
    
    _safeTransferFrom(
      path[0], msg.sender, pairFor(factory, path[0], path[1]), amounts[0]
    )
    
    _swap(amounts, path, to)
    
    return amounts
  end
  
  function :_swap, {
    amounts: [:uint256],
    path: [:address],
    _to: :address
  }, :internal, :virtual do
    for i in 0...(path.length - 1)
      input, output = path[i], path[i + 1]
      token0, _ = sortTokens(input, output)
      amountOut = amounts[i + 1]
      amount0Out, amount1Out = input == token0 ? [0, amountOut] : [amountOut, 0]
      to = i < path.length - 2 ? pairFor(factory, output, path[i + 2]) : _to

      UniswapV2Pair(pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, "")
    end
  end
  
  function :_safeTransferFrom, { token: :address, from: :address, to: :address, value: :uint256 }, :private do
    result = ERC20(token).transferFrom(from: from, to: to, amount: value)
    
    require(result, "ScribeSwap: TRANSFER_FAILED")
  end
  
  function :getAmountsOut, {
    factory: :address,
    amountIn: :uint256,
    path: [:address]
  }, :public, :view, returns: [:uint256] do
    require(path.length >= 2, 'UniswapV2Library: INVALID_PATH')
    
    amounts = array(:uint256)
    amounts[0] = amountIn
    
    for i in 0...(path.length - 1)
      reserveIn, reserveOut = getReserves(factory, path[i], path[i + 1])
      amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut)
    end
    
    return amounts
  end
  
  function :getAmountOut, {
    amountIn: :uint256,
    reserveIn: :uint256,
    reserveOut: :uint256
  }, :public, :view, returns: :uint256 do
    require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
    require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
    
    amountInWithFee = amountIn * 997;
    numerator = amountInWithFee * reserveOut
    denominator = reserveIn * 1000 + amountInWithFee
    amountOut = numerator.div(denominator)
    
    return amountOut
  end
  
  function :quote, {
    amountA: :uint256,
    reserveA: :uint256,
    reserveB: :uint256
  }, :public, :pure, returns: :uint256 do
    require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
    require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
    
    return (amountA * reserveB).div(reserveA);
  end
  
  function :getReserves, {
    factory: :address,
    tokenA: :address,
    tokenB: :address
  }, :public, :view, returns: { reserveA: :uint256, reserveB: :uint256 } do
    token0, _ = sortTokens(tokenA, tokenB)
    
    reserve0, reserve1, _ = UniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
    
    (reserveA, reserveB) = tokenA == token0 ? [reserve0, reserve1] : [reserve1, reserve0]
    
    return {
      reserveA: reserveA,
      reserveB: reserveB
    }
  end
  
  function :pairFor, {
    factory: :address,
    tokenA: :address,
    tokenB: :address
  }, :internal, :pure, returns: :address do
    token0, token1 = sortTokens(tokenA, tokenB)
    
    return create2_address(
      salt: keccak256(abi.encodePacked(token0, token1)),
      deployer: factory,
      contract_type: "UniswapV2Pair"
    )
  end
  
  function :sortTokens, { tokenA: :address, tokenB: :address }, :internal, :pure, returns: { token0: :address, token1: :address } do
    require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES')
    
    token0, token1 = tokenA.cast(:uint256) < tokenB.cast(:uint256) ? [tokenA, tokenB] : [tokenB, tokenA]
    
    require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS')
    
    return { token0: token0, token1: token1 }
  end
  
  function :userStats, {
    user: :address,
    tokenA: :address,
    tokenB: :address,
  }, :public, :view, returns: {
    userTokenABalance: :uint256,
    userTokenBBalance: :uint256,
    tokenAName: :string,
    tokenBName: :string,
    tokenAReserves: :uint256,
    tokenBReserves: :uint256,
    userLPBalance: :uint256,
    pairAddress: :address
  } do
    tokenAReserves = 0
    tokenBReserves = 0
    userLPBalance = 0
    
    if UniswapV2Factory(s.factory).getPair(tokenA, tokenB) != address(0)
      tokenAReserves, tokenBReserves = getReserves(s.factory, tokenA, tokenB)
      
      pair = UniswapV2Factory(s.factory).getPair(tokenA, tokenB)
      userLPBalance = UniswapV2ERC20(pair).balanceOf(user)
    end
    
    return {
      userTokenABalance: ERC20(tokenA).balanceOf(user),
      userTokenBBalance: ERC20(tokenB).balanceOf(user),
      tokenAName: ERC20(tokenA).name(),
      tokenBName: ERC20(tokenB).name(),
      tokenAReserves: tokenAReserves,
      tokenBReserves: tokenBReserves,
      userLPBalance: userLPBalance,
      pairAddress: pair
    }
  end
end
