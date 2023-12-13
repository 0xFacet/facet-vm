require 'rails_helper'

describe 'FacetSwapV1Router contract' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:charlie) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let(:daryl) { "0xdddddddddddddddddddddddddddddddddddddddd" }
  let(:frank) { "0xffffffffffffffffffffffffffffffffffffffff" }
  let(:all_addresses) { [user_address, alice, bob, charlie] }
  let(:start_time) { Time.zone.now }
  
  before(:all) do
    update_supported_contracts(
      'FacetSwapV1FactoryVariableFee',
      'FacetSwapV1RouterVariableFee',
      'FacetSwapV1PairVariableFee',
      'FacetSwapV1Router',
      'FacetSwapV1Pair',
      'FacetSwapV1Factory',
      'StubERC20'
    )
  end
  
  def sqrt(integer)
    integer = TypedVariable.create_or_validate(:uint256, integer)

    Math.sqrt(integer.value.to_d).floor
  end
  
  it 'performs a token swap' do
    factory_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "FacetSwapV1Factory",
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
    
    tokenX_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "StubERC20",
          args: { name: "Token X" }
        }
      }
    )
    token_x_address = tokenX_deploy_receipt.address

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

    weth_address = token_a_address
    
    router_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "FacetSwapV1Router",
          args: { _factory: factory_address, _WETH: weth_address }
        }
      }
    )
    router_address = router_deploy_receipt.address
    
    deploy_receipts = {
      "tokenA": tokenA_deploy_receipt,
      "tokenB": tokenB_deploy_receipt,
      "tokenX": tokenX_deploy_receipt,
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
    
    create_pair_receipt2 = trigger_contract_interaction_and_expect_success(
      from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
      payload: {
        to: factory_address,
        data: {
          function: "createPair",
          args: {
            tokenA: deploy_receipts[:tokenA].address,
            tokenB: deploy_receipts[:tokenX].address
          }
        }
      }
    )
    
    create_pair_receipt3 = trigger_contract_interaction_and_expect_success(
      from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
      payload: {
        to: factory_address,
        data: {
          function: "createPair",
          args: {
            tokenA: deploy_receipts[:tokenX].address,
            tokenB: deploy_receipts[:tokenB].address
          }
        }
      }
    )
    
    pair_address = create_pair_receipt.logs.detect{|i| i['event'] == 'PairCreated'}['data']['pair']
    pair_address2 = create_pair_receipt2.logs.detect{|i| i['event'] == 'PairCreated'}['data']['pair']
    pair_address3 = create_pair_receipt3.logs.detect{|i| i['event'] == 'PairCreated'}['data']['pair']
    
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
    
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")

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
    
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")
    
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
  
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")
  
    amountOut = 300.ether
    amountInMax = 3_000.ether
  
    numerator = reserveA * amountOut * 1000
    denominator = (reserveB - amountOut) * 997
    expectedIn = (numerator.div(denominator)) + 1
  
    swap_receipt = nil

    t = Benchmark.ms do
      swap_receipt = trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          to: router_address,
          data: {
            function: "swapTokensForExactTokens",
            args: {
              amountOut: amountOut,
              amountInMax: amountInMax,
              path: [token_a_address, token_b_address],
              to: user_address,
              deadline: Time.now.to_i + 300
            }
          }
        }
      )
    end
    # ap t
  
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
  
    token_a_diff = token_a_balance_before - token_a_balance_after
    expect(token_a_diff).to eq(expectedIn)
  
    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(amountOut)
    
    
    v2 = RubidityTranspiler.transpile_and_get("FacetSwapV1RouterVariableFee")

    
    migrationCalldata = {
      function: "onUpgrade",
      args: {
        owner: user_address,
        initialPauseState: true
      }
    }
    
    upgrade_tx = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "upgradeAndCall",
          args: {
            newHash: v2.init_code_hash,
            newSource: v2.source_code,
            migrationCalldata: migrationCalldata.to_json
          }
        }
      }
    )
    
    v2 = RubidityTranspiler.transpile_and_get("FacetSwapV1FactoryVariableFee")

    
    upgrade_tx = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: factory_address,
        data: {
          function: "upgrade",
          args: {
            newHash: v2.init_code_hash,
            newSource: v2.source_code,
          }
        }
      }
    )
    
    v2 = RubidityTranspiler.transpile_and_get("FacetSwapV1PairVariableFee")
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: factory_address,
        data: {
          function: "upgradePairs",
          args: {
            pairs: [pair_address2],
            newHash: v2.init_code_hash,
            newSource: v2.source_code,
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: factory_address,
        data: {
          function: "upgradePairs",
          args: {
            pairs: [pair_address3, pair_address],
            newHash: v2.init_code_hash,
            newSource: "",
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: factory_address,
        data: {
          function: "setLpFeeBPS",
          args: 100
        }
      }
    )

     trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "updateProtocolFee",
          args: 30
        }
      }
    )
    
    unpause = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "unpause"
        }
      }
    )
    
    [user_address, alice, bob, charlie].each do |address|
      [:tokenA, :tokenB].each do |token|
        trigger_contract_interaction_and_expect_success(
          from: address,
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
          from: address,
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
        from: address,
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
    end
    
    origAmountADesired = amountADesired = 5_000.ether
    origAmountBDesired = amountBDesired = 5_000.ether - 2_000.ether
    amountAMin = 0
    amountBMin = 0
    
    [charlie, user_address, alice, bob].each do |addr|
      add_liquidity_receipt = trigger_contract_interaction_and_expect_success(
        from: addr,
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
              to: addr,
              deadline: Time.now.to_i + 300
            }
          }
        }
      )
      
      amountADesired -= amountADesired / 5
      amountBDesired -= amountBDesired / 5
      amountAMin -= amountAMin / 5
      amountBMin -= amountBMin / 5
    end

    protocolFeeBPS = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "protocolFeeBPS",
    )
    
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
    
    router_fee_balance_before = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: router_address
    )
    
    reserves = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )
    
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")
    
    lp_fee_bps = ContractTransaction.make_static_call(
      contract: factory_address,
      function_name: "lpFeeBPS"
    )

    amountIn = 1_000.ether
    first_swap_amount_in = amountIn
    amountOutMin = 300.ether
    
    feeFactor = (10000 - protocolFeeBPS) / 10000.to_d
    
    feeAmount = amountIn - (amountIn * feeFactor)
    amountInWithFee = amountIn - feeAmount
    
    numerator = amountInWithFee * (1000 - lp_fee_bps / 10) * reserveB
    denominator = (reserveA * 1000) + (amountInWithFee * (1000 - lp_fee_bps / 10))
    expectedOut = numerator.div(denominator)
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "swapExactTokensForTokens",
          args: {
            amountIn: amountIn,
            amountOutMin: 0,
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
    
    event = swap_receipt.logs.detect{|l| l['event'] == "FeeAdjustedSwap"}

    expect(event['data']['inputAmount']).to eq(amountIn)
    expect(event['data']['outputAmount']).to eq(expectedOut)
    
    router_fee_balance_after_one = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: router_address
    )
    
    net_fee_amount = router_fee_balance_after_one - router_fee_balance_before
    expect(net_fee_amount).to eq(feeAmount)
    
    second_swap_amount_in = 500.ether
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "swapExactTokensForTokens",
          args: {
            amountIn: second_swap_amount_in,
            amountOutMin: 0,
            path: [token_a_address, token_b_address],
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    router_fee_balance_after_two = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: router_address
    )
    
    net_fee_amount = router_fee_balance_after_two - router_fee_balance_after_one
    expect(net_fee_amount).to eq(second_swap_amount_in - (second_swap_amount_in * feeFactor))
    
    token_a_balance_before = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    token_b_balance_before = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    reserves = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )
  
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")
  
    amountOut = 300.ether
    amountInMax = 3_000.ether
    
    numerator = reserveA * amountOut * 1000
    denominator = (reserveB - amountOut) * (1000 - lp_fee_bps / 10)
    expectedIn = (numerator.div(denominator)) + 1
    
    feeAmount = (expectedIn * protocolFeeBPS) / 10000
    
    realExpectedIn = expectedIn + feeAmount
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: charlie,
      payload: {
        to: router_address,
        data: {
          function: "swapTokensForExactTokens",
          args: {
            amountOut: amountOut,
            amountInMax: amountInMax,
            path: [token_a_address, token_b_address],
            to: charlie,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    token_a_balance_after = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: charlie
    )
  
    token_b_balance_after = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    token_a_diff = token_a_balance_before - token_a_balance_after
    expect(token_a_diff).to eq(realExpectedIn)
  
    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(amountOut)
    
    event = swap_receipt.logs.detect{|l| l['event'] == "FeeAdjustedSwap"}
    
    expect(event['data']['inputAmount']).to eq(realExpectedIn)
    expect(event['data']['outputAmount']).to eq(amountOut)
    
    router_fee_balance_after_three = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: router_address
    )
    
    net_fee_amount = router_fee_balance_after_three - router_fee_balance_after_two
    expect(net_fee_amount).to eq(feeAmount)
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    token_a_balance_before = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    token_b_balance_before = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    reserves = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )
  
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")
  
    amountOut = 300.ether
    amountInMax = 3_000.ether
    
    feeAmount = (amountOut * protocolFeeBPS) / 10000
    realAmountOut = amountOut + feeAmount
    
    numerator = reserveB * realAmountOut * 1000
    denominator = (reserveA - realAmountOut) * (1000 - lp_fee_bps / 10)
    expectedIn = (numerator.div(denominator)) + 1
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: charlie,
      payload: {
        to: router_address,
        data: {
          function: "swapTokensForExactTokens",
          args: {
            amountOut: amountOut,
            amountInMax: amountInMax,
            path: [token_b_address, token_a_address],
            to: charlie,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    token_a_balance_after = ContractTransaction.make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: charlie
    )
  
    token_b_balance_after = ContractTransaction.make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    token_a_diff = token_a_balance_after - token_a_balance_before
    expect(token_a_diff).to eq(amountOut)
  
    token_b_diff = token_b_balance_before - token_b_balance_after
    expect(token_b_diff).to eq(expectedIn)
    
    event = swap_receipt.logs.detect{|l| l['event'] == "FeeAdjustedSwap"}
    
    expect(event['data']['feeAmount']).to eq(feeAmount)
    expect(event['data']['inputAmount']).to eq(expectedIn)
    expect(event['data']['outputAmount']).to eq(amountOut)
    
    
    
    
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "withdrawFees",
          args: {
            to: user_address
          }
        }
      }
    )
    
    
    
    
    
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
    
    router_fee_balance_before = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: router_address
    )
    
    reserves = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )
    
    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")

    amountIn = 1_000.ether
        
    amountInWithFee = amountIn
    
    numerator = amountInWithFee * (1000 - lp_fee_bps / 10) * reserveA
    denominator = (reserveB * 1000) + (amountInWithFee * (1000 - lp_fee_bps / 10))
    expectedOut = numerator.div(denominator)
    
    fee = expectedOut * protocolFeeBPS / 10_000
    expectedOutWithFee = expectedOut - fee
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "swapExactTokensForTokens",
          args: {
            amountIn: amountIn,
            amountOutMin: 0,
            path: [token_b_address, token_a_address],
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
    
    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(-1 * amountIn)
    
    token_a_diff = token_a_balance_after - token_a_balance_before
    
    expect(token_a_diff).to eq(expectedOutWithFee)
    
    event = swap_receipt.logs.detect{|l| l['event'] == "FeeAdjustedSwap"}

    expect(event['data']['inputAmount']).to eq(amountIn)
    expect(event['data']['outputAmount']).to eq(expectedOutWithFee)
    expect(event['data']['feeAmount']).to eq(fee)
    
    router_fee_balance = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: router_address
    )
    
    expect(router_fee_balance).to eq(fee)

  end
end
