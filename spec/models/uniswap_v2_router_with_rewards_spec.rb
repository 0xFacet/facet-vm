require 'rails_helper'

describe 'UniswapV2Router contract' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0x000000000000000000000000000000000000000a" }
  let(:bob) { "0x000000000000000000000000000000000000000b" }
  let(:charlie) { "0x000000000000000000000000000000000000000c" }
  let(:daryl) { "0x000000000000000000000000000000000000000d" }
  let(:all_addresses) { [user_address, alice, bob, charlie] }
  let(:start_time) { Time.zone.now }
  
  before(:all) do
    RubidityFile.add_to_registry('spec/fixtures/StubERC20.rubidity')
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
          args: {
            _factory: factory_address,
            _WETH: weth_address,
            feeBPS: 1_000,
            stakerFeePct: 75,
            swapperFeePct: 15,
            protocolFeePct: 10,
            feeAdmin: daryl
          }
        }
      }
    )
    router_address = router_deploy_receipt.address
    router_contract = Contract.find_by_address(router_address)
    rc = router_contract
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
    
    alice_stake_amount = 1000.ether
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: router_address,
        data: {
          function: "stakeLP",
          args: {
            lpToken: pair_address,
            amount: alice_stake_amount,
          }
        }
      }
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
    
    feeBPS = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "feeBPS"
    )
    
    stakerPct = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "stakerFeePct"
    )
    
    protocolPct = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "protocolFeePct"
    )
    
    amountIn = 1_000.ether
    first_swap_amount_in = amountIn
    amountOutMin = 300.ether
    
    feeFactor = (10000 - feeBPS) / 10000.to_d
    numerator = amountIn * feeFactor * 997 * reserveB
    denominator = (reserveA * 1000) + (amountIn * feeFactor * 997)
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
    
    alice_initial_reward_withdraw = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "pendingStakingRewards",
      function_args: [alice, pair_address]
    )
    
    current_weth_balance = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    withdrawRewards_receipt = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: router_address,
        data: {
          function: "withdrawStakingRewards",
          args: {
            lpToken: pair_address
          }
        }
      }
    )
    
    new_weth_balance = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    expect(current_weth_balance + alice_initial_reward_withdraw).to eq(new_weth_balance)
    
    total_staked = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "totalStakedLP",
      function_args: [pair_address]
    )
    
    expect(total_staked).to eq(alice_stake_amount)
    
    bob_stake_amount = 500.ether
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        to: router_address,
        data: {
          function: "stakeLP",
          args: {
            lpToken: pair_address,
            amount: bob_stake_amount,
          }
        }
      }
    )
    
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
    
    effectiveFee = feeBPS * stakerPct / 100
    
    rewards_per_share = 0
    fee_in_first_swap = (first_swap_amount_in * effectiveFee).div(10_000)
    total_staked = alice_stake_amount
    rewards_per_share += (fee_in_first_swap * 1.ether).div(total_staked)
    alice_reward_debt = 0
    
    alice_reward = (rewards_per_share * alice_stake_amount).div(1.ether) - alice_reward_debt
    
    expect(alice_reward).to eq(alice_initial_reward_withdraw)
    
    alice_reward_debt = (rewards_per_share * alice_stake_amount).div(1.ether)
    
    total_staked += bob_stake_amount
    
    bob_reward_debt = (rewards_per_share * bob_stake_amount).div(1.ether)
    
    fee_in_second_swap = (second_swap_amount_in * effectiveFee).div(10_000)

    rewards_per_share += (fee_in_second_swap * 1.ether).div(total_staked)

    alice_pending_rewards = (rewards_per_share * alice_stake_amount).div(1.ether) - alice_reward_debt
    bob_pending_rewards = (rewards_per_share * bob_stake_amount).div(1.ether) - bob_reward_debt
    
    effectiveProtocolFee = feeBPS * protocolPct / 100
    
    protocol_fee_amt = ((first_swap_amount_in + second_swap_amount_in) * effectiveProtocolFee).div(10_000)
    
    effectiveSwapFee = feeBPS * (100 - stakerPct - protocolPct) / 100
    
    swap_fee_amt = ((first_swap_amount_in + second_swap_amount_in) * effectiveSwapFee).div(10_000)
    
    expect(swap_fee_amt).to eq(
      rc.reload['current_state']['swapperRewardsPool'] + rc['current_state']['swapperRewards'].values.sum
    )
    
    initial_admin_balance = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    withdraw_protocol_rewards = trigger_contract_interaction_and_expect_success(
      from: daryl,
      payload: {
        to: router_address,
        data: {
          function: "withdrawProtocolRewards",
          args: {
            to: daryl
          }
        }
      }
    )
    
    expect(ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: daryl
    )).to eq(protocol_fee_amt + initial_admin_balance)
    
    expect(ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "pendingStakingRewards",
      function_args: [bob, pair_address]
    )).to eq(bob_pending_rewards)
    
    expect(ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "pendingStakingRewards",
      function_args: [alice, pair_address]
    )).to eq(alice_pending_rewards)
    
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
    
    feeAmount = (amountOut * feeBPS) / 10_000.to_d

    adjustedAmountOut = amountOut + feeAmount
  
    numerator = reserveA * adjustedAmountOut * 1000
    denominator = (reserveB - adjustedAmountOut) * 997
    expectedIn = (numerator.div(denominator)) + 1
    
    # ap rc.reload['current_state']['protocolFeePool'] / 1.ether
    # ap rc.reload['current_state']#['protocolFeePool'] / 1.ether
    
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
    expect(token_a_diff).to eq(expectedIn)
  
    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(amountOut)
    
    current_weth_balance_bob = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: bob
    )
    
    pending_rewards_bob = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "pendingStakingRewards",
      function_args: [bob, pair_address]
    )
    
    withdrawRewards_receipt_bob = trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        to: router_address,
        data: {
          function: "withdrawStakingRewards",
          args: {
            lpToken: pair_address
          }
        }
      }
    )
    
    new_weth_balance_bob = ContractTransaction.make_static_call(
      contract: weth_address,
      function_name: "balanceOf",
      function_args: bob
    )
    
    expect(new_weth_balance_bob).to eq(current_weth_balance_bob + pending_rewards_bob)
    
    total_staked = ContractTransaction.make_static_call(
      contract: router_address,
      function_name: "totalStakedLP",
      function_args: [pair_address]
    )
    
    expect(total_staked).to eq(alice_stake_amount + bob_stake_amount)
    
    alice_lp_balance = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    stake_withdraw_amount = 100.ether
    
    stake_withdraw_receipt = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: router_address,
        data: {
          function: "unstakeLP",
          args: {
            lpToken: pair_address,
            amount: stake_withdraw_amount
          }
        }
      }
    )
    
    alice_lp_balance_after = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    expect(alice_lp_balance_after).to eq(alice_lp_balance + stake_withdraw_amount)
    
    sw_withdraw = trigger_contract_interaction_and_expect_success(
      from: charlie,
      payload: {
        to: router_address,
        data: {
          function: "withdrawSwapperRewards"
        }
      }
    )
  end
end
