class Contracts::UniswapV2Factory < ContractImplementation
  address :public, :feeTo
  address :public, :feeToSetter

  mapping ({ address: mapping({ address: :address })}), :public, :getPair
  array :address, :public, :allPairs

  event :PairCreated, { token0: :address, token1: :address, pair: :address, pairLength: :uint256 }

  constructor(_feeToSetter: :address) {
    s.feeToSetter = _feeToSetter
  }

  function :allPairsLength, :public, :view, returns: :uint256 do
    return allPairs.length
  end

  function :createPair, { tokenA: :address, tokenB: :address }, :public, returns: :address do
    require(tokenA != tokenB, 'Scribeswap: IDENTICAL_ADDRESSES')
    
    token0 = tokenA.cast(:uint256) < tokenB.cast(:uint256) ? tokenA : tokenB
    token1 = tokenA.cast(:uint256) > tokenB.cast(:uint256) ? tokenB : tokenA
    
    require(token0 != address(0), "Scribeswap: ZERO_ADDRESS");
    require(s.getPair[token0][token1] == address(0), "Scribeswap: PAIR_EXISTS");
    
    salt = keccak256(token0.cast(:uint256) + token1.cast(:uint256))
    
    pair = new UniswapV2Pair({ salt: salt })
    pair.init(token0, token1)
    
    s.getPair[token0][token1] = pair;
    s.getPair[token1][token0] = pair;
    
    s.allPairs.push(pair)
    emit(:PairCreated, { token0: token0, token1: token1, pair: pair, pairLength: s.allPairs.length })
    
    return pair
  end

  function :setFeeTo, { _feeTo: :address }, :public do
    require(msg.sender == feeToSetter, "Scribeswap: FORBIDDEN")
    
    s.feeTo = _feeTo
  end

  function :setFeeToSetter, { _feeToSetter: :address }, :public do
    require(msg.sender == feeToSetter, "Scribeswap: FORBIDDEN")
    
    s.feeToSetter = _feeToSetter
  end
end