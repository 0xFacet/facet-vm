require 'rails_helper'

class Contracts::StubERC20 < ContractImplementation
  is :ERC20
  
  constructor(name: :string) {
    ERC20.constructor(name: name, symbol: "symbol", decimals: 18)
  }
  
  function :mint, { amount: :uint256 }, :public do
    _mint(to: msg.sender, amount: amount)
  end
end


describe 'UniswapV2Router contract' do
  def sqrt(integer)
    integer = TypedVariable.create_or_validate(:uint256, integer)

    Math.sqrt(integer.value.to_d).floor
  end
  
  it 'performs a token swap' do
    user_address = "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
    
    zap = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UniswapSetupZap"
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
      payload: {
        to: zap.contract_address,
        data: {
          function: "doZap",
          args: {}
        }
      }
    )
    
    res = ContractTransaction.make_static_call(
      contract: zap.contract_address,
      function_name: "lastZap"
    )
    
    args = res.values_at(:router, :factory, :tokenA, :tokenB)
    
    ContractTransaction.make_static_call(
      contract: zap.contract_address,
      function_name: "userStats",
      function_args: [user_address, *args],
    )
    
    args = res.values_at(:tokenA, :tokenB)
    
    ContractTransaction.make_static_call(
      contract: res[:router],
      function_name: "userStats",
      function_args: [user_address, *args],
    )
    
    factory_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UniswapV2Factory",
          args: { _feeToSetter: user_address }
        }
      }
    )
    factory_address = factory_deploy_receipt.address

    tokenA_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "StubERC20",
          args: { name: "Token A" }
        }
      }
    )
    token_a_address = tokenA_deploy_receipt.address

    tokenB_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "StubERC20",
          args: { name: "Token B" }
        }
      }
    )
    token_b_address = tokenB_deploy_receipt.address

    weth_address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    
    router_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UniswapV2Router",
          args: { _factory: factory_address, _WETH: weth_address }
        }
      }
    )
    router_address = router_deploy_receipt.address
    
    deploy_receipts = {
      "tokenA": tokenA_deploy_receipt,
      "tokenB": tokenB_deploy_receipt,
    }.with_indifferent_access
    
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
      payload: {
        to: factory_address,
        data: {
          function: "createPair",
          args: {
            tokenA: deploy_receipts[:tokenA].address,
            tokenB: deploy_receipts[:tokenB].address
          }
        }
      }
    )
    
    pair_address = create_pair_receipt.logs.detect{|i| i['event'] == 'PairCreated'}['data']['pair']
    
    [:tokenA, :tokenB].each do |token|
      trigger_contract_interaction_and_expect_success(
        from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
        payload: {
          to: deploy_receipts[token].address,
          data: {
            function: "mint",
            args: {
              amount: 100_000.ether
            }
          }
        }
      )

      trigger_contract_interaction_and_expect_success(
        from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
        payload: {
          to: deploy_receipts[token].address,
          data: {
            function: "approve",
            args: {
              spender: router_address,
              amount: (2 ** 256 - 1)
            }
          }
        }
      )
    end
    
    trigger_contract_interaction_and_expect_success(
      from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
      payload: {
        to: pair_address,
        data: {
          function: "approve",
          args: {
            spender: router_address,
            amount: (2 ** 256 - 1)
          }
        }
      }
    )
    
    amountADesired = 5_000.ether
    amountBDesired = 5_000.ether - 2_000.ether
    amountAMin = 1_000.ether
    amountBMin = 1_000.ether
    
    add_liquidity_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "addLiquidity",
          args: {
            tokenA: token_a_address,
            tokenB: token_b_address,
            amountADesired: amountADesired,
            amountBDesired: amountBDesired,
            amountAMin: amountAMin,
            amountBMin: amountBMin,
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    lp_balance = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    expect(lp_balance).to eq(sqrt(amountADesired * amountBDesired) - 1000)
    
    my_current_liquidity = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    liquidity_to_remove = my_current_liquidity.div(2)  # remove 50% of liquidity
    
    reserves = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )
    
    reserveA, reserveB = reserves.values_at(:reserveA, :reserveB)

    total_lp_supply = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "totalSupply"
    )
    
    my_share = liquidity_to_remove.div(total_lp_supply)
    
    amountA_estimated = my_share * reserveA
    amountB_estimated = my_share * reserveB
    
    acceptable_slippage = 0.01  # 1% slippage
    amountAMin = (amountA_estimated * (1 - acceptable_slippage)).to_i
    amountBMin = (amountB_estimated * (1 - acceptable_slippage)).to_i

    # Get the initial LP token balance and token balances
    initial_lp_balance = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    initial_token_a_balance = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    initial_token_b_balance = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    remove_liquidity_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "removeLiquidity",
          args: {
            tokenA: token_a_address,
            tokenB: token_b_address,
            liquidity: liquidity_to_remove,
            amountAMin: amountAMin,
            amountBMin: amountBMin,
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    # Check final balances
    final_lp_balance = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    final_token_a_balance = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    final_token_b_balance = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    # Validate LP tokens are burned
    expect(final_lp_balance).to eq(initial_lp_balance - liquidity_to_remove)

    # Validate received amounts for tokenA and tokenB
    expect(final_token_a_balance - initial_token_a_balance).to be >= amountAMin
    expect(final_token_b_balance - initial_token_b_balance).to be >= amountBMin

    token_a_balance_before = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    token_b_balance_before = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    reserves = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )
    
    reserveA, reserveB = reserves.values_at(:reserveA, :reserveB)
    
    amountIn = 1_000.ether
    amountOutMin = 300.ether

    numerator = amountIn * 997 * reserveB;
    denominator = (reserveA * 1000) + (amountIn * 997);
    expectedOut = numerator.div(denominator)
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "swapExactTokensForTokens",
          args: {
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            path: [token_a_address, token_b_address],
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    token_a_balance_after = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    token_b_balance_after = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    token_a_diff = token_a_balance_after - token_a_balance_before
    expect(token_a_diff).to eq(-1 * amountIn)
    
    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(expectedOut)
  end
end
