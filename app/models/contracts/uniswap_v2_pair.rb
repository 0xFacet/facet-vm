class Contracts::UniswapV2Pair < ContractImplementation
  uint256 :public, :MINIMUM_LIQUIDITY
  # bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

  address :public, :factory
  address :public, :token0
  address :public, :token1

  uint112 :private, :reserve0
  uint112 :private, :reserve1
  uint32  :private, :blockTimestampLast

  uint256 :public, :price0CumulativeLast
  uint256 :public, :price1CumulativeLast;
  uint256 :public, :kLast

  uint256 :private, :unlocked
  
  function :getReserves, {}, :public, :view, returns: { _reserve0: :uint112, _reserve1: :uint112, _blockTimestampLast: :uint32 } do
    return {
      _reserve0: reserve0,
      _reserve1: reserve1,
      _blockTimestampLast: blockTimestampLast
    }
  end
  
  function :_safeTransfer, { token: :address, to: :address, value: :uint256 }, :private do
    result = ERC20(token).transfer(to: to, value: value)
    
    require(result, "UniswapV2: TRANSFER_FAILED")
  end
  
  event :Mint, { sender: :address, amount0: :uint256, amount1: :uint256 }
  event :Burn, { sender: :address, amount0: :uint256, amount1: :uint256, to: :address }
  event :Swap, { 
    sender: :address, 
    amount0In: :uint256, 
    amount1In: :uint256, 
    amount0Out: :uint256, 
    amount1Out: :uint256, 
    to: :address 
  }
  event :Sync, { reserve0: :uint112, reserve1: :uint112 }
  
  constructor() {
    s.factory = msg.sender
    
    s.MINIMUM_LIQUIDITY = 10 ** 3
    s.unlocked = 1
  }
  
  # Can't call it initialize bc of Ruby (for now)
  function :init, { _token0: :address, _token1: :address }, :external do
    require(msg.sender == factory, 'UniswapV2: FORBIDDEN')

    s.token0 = _token0;
    s.token1 = _token1;
  end
  
  # function :_update, { balance0: :uint256, balance1: :uint256, _reserve0: :uint112, _reserve1: :uint112 }, :private do
  #   blockTimestamp = uint32(block.timestamp % 2**32)
  #   timeElapsed = blockTimestamp - blockTimestampLast # overflow is desired
  #   if timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0
  #     # * never overflows, and + overflow is desired
  #     price0CumulativeLast += _reserve1 / _reserve0 * timeElapsed
  #     price1CumulativeLast += _reserve0 / _reserve1 * timeElapsed
  #   end
    
  #   s.reserve0 = uint112(balance0)
  #   s.reserve1 = uint112(balance1)
    
  #   s.blockTimestampLast = blockTimestamp
  #   emit :Sync, reserve0: reserve0, reserve1: reserve1
  # end
  
  # function :_mintFee, { _reserve0: :uint112, _reserve1: :uint112 }, :private, returns: :bool do
  #   feeTo = IUniswapV2Factory(s.factory).feeTo
  #   feeOn = feeTo != address(0)
  #   _kLast = kLast # gas savings
  #   if feeOn
  #     if _kLast != 0
  #       rootK = Math.sqrt(_reserve0 * _reserve1)
  #       rootKLast = Math.sqrt(_kLast)
  #       if rootK > rootKLast
  #         numerator = totalSupply * (rootK - rootKLast)
  #         denominator = rootK * 5 + rootKLast
  #         liquidity = numerator / denominator
  #         _mint(feeTo, liquidity) if liquidity > 0
  #       end
  #     end
  #   elsif _kLast != 0
  #     kLast = 0
  #   end
  #   feeOn
  # end
  
  # function :mint, { to: :address }, :external, returns: :uint256 do
  #   require(unlocked == 1, 'UniswapV2: LOCKED');
    
  #   _reserve0, _reserve1, _ = getReserves # gas savings
  #   balance0 = ERC20(s.token0).balanceOf(address(this))
  #   balance1 = ERC20(s.token1).balanceOf(address(this))
  #   amount0 = balance0 - _reserve0
  #   amount1 = balance1 - _reserve1
  
  #   feeOn = _mintFee(_reserve0, _reserve1)
  #   _totalSupply = s.totalSupply # gas savings, must be defined here since totalSupply can update in _mintFee
  #   if _totalSupply == 0
  #     liquidity = Math.sqrt(amount0 * amount1) - s.minimum_liquidity
  #     _mint(address(0), s.minimum_liquidity) # permanently lock the first MINIMUM_LIQUIDITY tokens
  #   else
  #     liquidity = [amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1].min
  #   end
  #   require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED')
  #   _mint(to, liquidity)
  
  #   _update(balance0, balance1, _reserve0, _reserve1)
  #   kLast = reserve0 * reserve1 if feeOn # reserve0 and reserve1 are up-to-date
    
  #   emit :Mint, sender: msg.sender, amount0: amount0, amount1: amount1
  # end
  
  # function :burn, { to: :address }, :external, :lock, returns: { amount0: :uint256, amount1: :uint256 } do
  #   _reserve0, _reserve1, _ = getReserves # gas savings
  #   _token0 = token0 # gas savings
  #   _token1 = token1 # gas savings
  #   balance0 = ERC20(_token0).balanceOf(address(this))
  #   balance1 = ERC20(_token1).balanceOf(address(this))
  #   liquidity = balanceOf[address(this)]
  
  #   feeOn = _mintFee(_reserve0, _reserve1)
  #   _totalSupply = totalSupply # gas savings, must be defined here since totalSupply can update in _mintFee
  #   amount0 = liquidity * balance0 / _totalSupply # using balances ensures pro-rata distribution
  #   amount1 = liquidity * balance1 / _totalSupply # using balances ensures pro-rata distribution
  #   require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED')
  #   _burn(address(this), liquidity)
  #   _safeTransfer(_token0, to, amount0)
  #   _safeTransfer(_token1, to, amount1)
  #   balance0 = ERC20(_token0).balanceOf(address(this))
  #   balance1 = ERC20(_token1).balanceOf(address(this))
  
  #   _update(balance0, balance1, _reserve0, _reserve1)
  #   kLast = reserve0 * reserve1 if feeOn # reserve0 and reserve1 are up-to-date
  #   emit :Burn, sender: msg.sender, amount0: amount0, amount1: amount1, to: to
  # end
  
  # function :swap, { amount0Out: :uint256, amount1Out: :uint256, to: :address, data: :bytes }, :external, :lock do
  #   require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT')
  #   _reserve0, _reserve1, _ = getReserves # gas savings
  #   require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY')
  
  #   balance0 = nil
  #   balance1 = nil
  #   _token0 = token0
  #   _token1 = token1
  #   require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO')
  #   _safeTransfer(_token0, to, amount0Out) if amount0Out > 0 # optimistically transfer tokens
  #   _safeTransfer(_token1, to, amount1Out) if amount1Out > 0 # optimistically transfer tokens
  #   IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data) if data.length > 0
  #   balance0 = ERC20(_token0).balanceOf(address(this))
  #   balance1 = ERC20(_token1).balanceOf(address(this))
  
  #   amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0
  #   amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0
  #   require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT')
  
  #   balance0Adjusted = balance0 * 1000 - amount0In * 3
  #   balance1Adjusted = balance1 * 1000 - amount1In * 3
  #   require(balance0Adjusted * balance1Adjusted >= uint(_reserve0) * _reserve1 * 1000**2, 'UniswapV2: K')
  
  #   _update(balance0, balance1, _reserve0, _reserve1)
  #   emit :Swap, sender: msg.sender, amount0In: amount0In, amount1In: amount1In, amount0Out: amount0Out, amount1Out: amount1Out, to: to
  # end
end