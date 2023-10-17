pragma :rubidity, "1.0.0"

import './UniswapV2Callee.rubidity'
import './UniswapV2ERC20.rubidity'

contract :IUniswapV2Factory, abstract: true do
  function :feeTo, :external, :view, returns: :address
end

contract :UniswapV2Pair, is: :UniswapV2ERC20 do
  uint256 :public, :MINIMUM_LIQUIDITY

  address :public, :factory
  address :public, :token0
  address :public, :token1

  uint112 :private, :reserve0
  uint112 :private, :reserve1
  uint32  :private, :blockTimestampLast

  uint256 :public, :price0CumulativeLast
  uint256 :public, :price1CumulativeLast
  uint256 :public, :kLast

  uint256 :private, :unlocked
  
  function :getReserves, {}, :public, :view, returns: {
    _reserve0: :uint112, _reserve1: :uint112, _blockTimestampLast: :uint32
  } do
    return {
      _reserve0: s.reserve0,
      _reserve1: s.reserve1,
      _blockTimestampLast: s.blockTimestampLast
    }
  end
  
  function :_safeTransfer, { token: :address, to: :address, value: :uint256 }, :private do
    result = ERC20(token).transfer(to: to, amount: value)
    
    require(result, "ScribeSwap: TRANSFER_FAILED")
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
  event :PreSwapReserves, { reserve0: :uint112, reserve1: :uint112 }
  
  constructor() {
    UniswapV2ERC20.constructor()
    
    s.factory = msg.sender
    
    s.MINIMUM_LIQUIDITY = 10 ** 3
    s.unlocked = 1
  }
  
  # Can't call it initialize bc of Ruby (for now)
  function :init, { _token0: :address, _token1: :address }, :external do
    require(msg.sender == s.factory, 'ScribeSwap: FORBIDDEN')

    s.token0 = _token0
    s.token1 = _token1
    
    return nil
  end
  
  function :_update, {
    balance0: :uint256,
    balance1: :uint256,
    _reserve0: :uint112,
    _reserve1: :uint112
  }, :private do
    require(balance0 <= (2 ** 112 - 1) && balance1 <= (2 ** 112 - 1), 'ScribeSwap: OVERFLOW')
    
    blockTimestamp = uint32(block.timestamp % 2 ** 32)
    timeElapsed = blockTimestamp - s.blockTimestampLast # overflow is desired
    
    if timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0
      # * never overflows, and + overflow is desired
      s.price0CumulativeLast += uint256(uqdiv(encode(_reserve1), _reserve0)) * timeElapsed
      s.price1CumulativeLast += uint256(uqdiv(encode(_reserve0), _reserve1)) * timeElapsed
    end
    
    emit :PreSwapReserves, reserve0: s.reserve0, reserve1: s.reserve1
    
    s.reserve0 = uint112(balance0)
    s.reserve1 = uint112(balance1)
    
    s.blockTimestampLast = blockTimestamp
    emit :Sync, reserve0: s.reserve0, reserve1: s.reserve1
  end
  
  function :encode, { y: :uint112 }, :internal, :pure, returns: :uint224 do
    return uint224(y) * (2 ** 112)
  end

  function :uqdiv, { x: :uint224, y: :uint112 }, :internal, :pure, returns: :uint224 do
    return x / uint224(y)
  end
  
  function :_mintFee, { _reserve0: :uint112, _reserve1: :uint112 }, :private, returns: :bool do
    feeTo = IUniswapV2Factory(s.factory).feeTo
    feeOn = feeTo != address(0)
    _kLast = s.kLast
    
    if feeOn
      if _kLast != 0
        rootK = sqrt(_reserve0 * _reserve1)
        rootKLast = sqrt(_kLast)
        if rootK > rootKLast
          numerator = totalSupply * (rootK - rootKLast)
          denominator = rootK * 5 + rootKLast
          liquidity = numerator.div(denominator)
          _mint(feeTo, liquidity) if liquidity > 0
        end
      end
    elsif _kLast != 0
      s.kLast = 0
    end
    feeOn
  end
  
  function :mint, { to: :address }, :public, returns: :uint256 do
    require(s.unlocked == 1, 'ScribeSwap: LOCKED')
    
    _reserve0, _reserve1, _ = getReserves
    
    balance0 = ERC20(s.token0).balanceOf(address(this))
    balance1 = ERC20(s.token1).balanceOf(address(this))
    amount0 = balance0 - _reserve0
    amount1 = balance1 - _reserve1
    
    feeOn = _mintFee(_reserve0, _reserve1)
    _totalSupply = s.totalSupply
    if _totalSupply == 0
      liquidity = sqrt(amount0 * amount1) - s.MINIMUM_LIQUIDITY
      _mint(address(0), s.MINIMUM_LIQUIDITY)
    else
      liquidity = [
        (amount0 * _totalSupply).div(_reserve0),
        (amount1 * _totalSupply).div(_reserve1)
      ].min
    end

    require(liquidity > 0, 'ScribeSwap: INSUFFICIENT_LIQUIDITY_MINTED')
    _mint(to, liquidity)
  
    _update(balance0, balance1, _reserve0, _reserve1)
    s.kLast = s.reserve0 * s.reserve1 if feeOn
    
    emit :Mint, sender: msg.sender, amount0: amount0, amount1: amount1
    
    return liquidity
  end
  
  function :burn, { to: :address }, :external, :lock, returns: { amount0: :uint256, amount1: :uint256 } do
    require(s.unlocked == 1, 'ScribeSwap: LOCKED')

    _reserve0, _reserve1, _ = getReserves
    _token0 = s.token0
    _token1 = s.token1
    balance0 = ERC20(_token0).balanceOf(address(this))
    balance1 = ERC20(_token1).balanceOf(address(this))
    liquidity = s.balanceOf[address(this)]
  
    feeOn = _mintFee(_reserve0, _reserve1)
    _totalSupply = s.totalSupply
    amount0 = (liquidity * balance0).div(_totalSupply)
    amount1 = (liquidity * balance1).div(_totalSupply)
    
    require(amount0 > 0 && amount1 > 0, 'ScribeSwap: INSUFFICIENT_LIQUIDITY_BURNED')
    _burn(address(this), liquidity)
    _safeTransfer(_token0, to, amount0)
    _safeTransfer(_token1, to, amount1)
    balance0 = ERC20(_token0).balanceOf(address(this))
    balance1 = ERC20(_token1).balanceOf(address(this))
  
    _update(balance0, balance1, _reserve0, _reserve1)
    s.kLast = s.reserve0 * s.reserve1 if feeOn
    
    emit :Burn, sender: msg.sender, amount0: amount0, amount1: amount1, to: to
    
    return { amount0: amount0, amount1: amount1 }
  end
  
  function :swap, { amount0Out: :uint256, amount1Out: :uint256, to: :address, data: :bytes }, :external do
    require(s.unlocked == 1, 'ScribeSwap: LOCKED')
    
    require(amount0Out > 0 || amount1Out > 0, 'ScribeSwap: INSUFFICIENT_OUTPUT_AMOUNT')
    _reserve0, _reserve1, _ = getReserves
    require(amount0Out < _reserve0 && amount1Out < _reserve1, 'ScribeSwap: INSUFFICIENT_LIQUIDITY')
  
    balance0 = 0
    balance1 = 0
    _token0 = s.token0
    _token1 = s.token1
    
    require(to != _token0 && to != _token1, 'ScribeSwap: INVALID_TO')
    
    _safeTransfer(_token0, to, amount0Out) if amount0Out > 0 # optimistically transfer tokens
    _safeTransfer(_token1, to, amount1Out) if amount1Out > 0 # optimistically transfer tokens
    
    UniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data) if data.length > 0
    
    balance0 = ERC20(_token0).balanceOf(address(this))
    balance1 = ERC20(_token1).balanceOf(address(this))

    amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0
    amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0

    require(amount0In > 0 || amount1In > 0, 'ScribeSwap: INSUFFICIENT_INPUT_AMOUNT')
  
    balance0Adjusted = balance0 * 1000 - amount0In * 3
    balance1Adjusted = balance1 * 1000 - amount1In * 3
    
    require(
      balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (1000 ** 2),
      'ScribeSwap: K'
    )
  
    _update(balance0, balance1, _reserve0, _reserve1)
    emit :Swap, sender: msg.sender, amount0In: amount0In, amount1In: amount1In, amount0Out: amount0Out, amount1Out: amount1Out, to: to
  end
  
  function :skim, { to: :address }, :external do
    require(s.unlocked == 1, 'ScribeSwap: LOCKED')
    
    _token0 = s.token0
    _token1 = s.token1
    
    _safeTransfer(_token0, to, ERC20(_token0).balanceOf(address(this)) - s.reserve0)
    _safeTransfer(_token1, to, ERC20(_token1).balanceOf(address(this)) - s.reserve1)
  end
  
  function :sync, {}, :external do
    require(s.unlocked == 1, 'ScribeSwap: LOCKED')
    
    _update(
      ERC20(s.token0).balanceOf(address(this)),
      ERC20(s.token1).balanceOf(address(this)),
      s.reserve0,
      s.reserve1
    )
  end
end
