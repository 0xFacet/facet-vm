require 'rails_helper'

describe 'UniswapV2Router contract' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0x000000000000000000000000000000000000000a" }
  let(:bob) { "0x000000000000000000000000000000000000000b" }
  let(:charlie) { "0x000000000000000000000000000000000000000c" }
  let(:all_addresses) { [user_address, alice, bob, charlie] }
  let(:start_time) { Time.zone.now }
  
  before(:all) do
    RubidityFile.add_to_registry('spec/fixtures/StubERC20.rubidity')
  end
  
  def sqrt(integer)
    integer = TypedVariable.create_or_validate(:uint256, integer)

    Math.sqrt(integer.value.to_d).floor
  end
  
  def stake_lp_tokens(from_address:, lp_token_address:, amount:, router_address:)
    trigger_contract_interaction_and_expect_success(
      from: from_address,
      payload: {
        to: router_address,
        data: {
          function: "stakeLP",
          args: {
            lpToken: lp_token_address,
            amount: amount
          }
        }
      }
    )
  end
  
  def days_from_now(days)
    now = 1698772517
    
    (now + days.days).to_i
  end
  
  it 'performs a token swap' do
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

    weth_address = token_a_address
    
    router_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UniswapV2RouterWithRewards",
          args: { _factory: factory_address, _WETH: weth_address, _feeBPS: 1_000 }
        }
      }
    )
    router_address = router_deploy_receipt.address
    router_contract = Contract.find_by_address(router_address)
    deploy_receipts = {
      "tokenA": tokenA_deploy_receipt,
      "tokenB": tokenB_deploy_receipt,
    }.with_indifferent_access
    
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
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
    amountAMin = 1_000.ether
    amountBMin = 1_000.ether
    
    [user_address, alice, bob, charlie].each do |addr|
      add_liquidity_receipt = trigger_contract_interaction_and_expect_success(
        block_timestamp: days_from_now(0),
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
              deadline: days_from_now(10000)
            }
          }
        }
      )
      
      amountADesired -= amountADesired / 5
      amountBDesired -= amountBDesired / 5
      amountAMin -= amountAMin / 5
      amountBMin -= amountBMin / 5
    end
    
    lp_balance = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    expect(lp_balance).to eq(sqrt(origAmountADesired * origAmountBDesired) - 1000)
    
    my_current_liquidity = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    participants = [user_address, alice, bob, charlie]

    # Amount to stake for each participant
    stake_amount = 1_000.ether
    
    # participants.each.with_index do |participant, i|
    [user_address].each.with_index do |participant, i|
      trigger_contract_interaction_and_expect_success(
        block_timestamp: days_from_now((i + 1) * 30),
        from: participant,
        payload: {
          to: router_address,
          data: {
            function: "stakeLP",
            args: {
              lpToken: pair_address,
              amount: stake_amount,
            }
          }
        }
      )
    
      # Validate staked amount for each participant
      staked_balance = ContractTransaction.make_static_call(
        contract: router_address,
        function_name: "stakedLP",
        function_args: [participant, pair_address]
      )
    
      expect(staked_balance).to eq(stake_amount)
      
      stake_amount -= stake_amount / 5
    end
    
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
      block_timestamp: days_from_now(100),
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
            deadline: days_from_now(10000)
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
    
    feeBPS = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "feeBPS"
    )
    
    # participants.each do |participant|
    #   initial_rewards = ContractTransaction.make_static_call(
    #     contract: router_address,
    #     function_name: "pendingRewards",
    #     function_args: [participant, pair_address]
    #   )
    #   expect(initial_rewards).to eq(0)
    # end
    
    amountIn = 1_000.ether
    amountOutMin = 300.ether
    
    feeFactor = (10000 - feeBPS) / 10000.to_d
    numerator = amountIn * feeFactor * 997 * reserveB
    denominator = (reserveA * 1000) + (amountIn * feeFactor * 997)
    expectedOut = numerator.div(denominator)
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      block_timestamp: days_from_now(200),
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
            deadline: days_from_now(10000)
          }
        }
      }
    )
    # binding.pry
    total = [user_address].sum do |participant|
      post_swap_rewards = ContractTransaction.make_static_call(
        block_timestamp: days_from_now(500),
        contract: router_address,
        function_name: "pendingRewards",
        function_args: [participant, pair_address]
      )
    end
    
    ap total
    router_contract.reload
    binding.pry
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
    
    total_staked = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "totalStakedLP",
      function_args: [pair_address]
    )

    expect(total_staked).to be >= stake_amount
    
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
    
    feeAmount = (amountOut * feeBPS) / 10_000.to_d

    adjustedAmountOut = amountOut + feeAmount
  
    numerator = reserveA * adjustedAmountOut * 1000
    denominator = (reserveB - adjustedAmountOut) * 997
    expectedIn = (numerator.div(denominator)) + 1
    
    swap_receipt = trigger_contract_interaction_and_expect_success(
      block_timestamp: days_from_now(300),
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
            deadline: days_from_now(10000)
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
  
    token_a_diff = token_a_balance_before - token_a_balance_after
    expect(token_a_diff).to eq(expectedIn)
  
    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(amountOut)
    
    stake_withdraw_receipt = trigger_contract_interaction_and_expect_success(
      block_timestamp: days_from_now(500),
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "withdrawRewards",
          args: {
            lpToken: pair_address
          }
        }
      }
    )
  end
end
