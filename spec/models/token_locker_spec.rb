require 'rails_helper'

describe 'TokenLocker contract' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:token_address) { "0xTokenAddressHere" }
  let(:lock_id) { 1 }
  let(:amount) { 1000 }

  before(:all) do
    update_supported_contracts(
      'FacetSwapV1Locker',
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
  
  it 'locks tokens' do
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
    token_c_address = token_x_address
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
    
    [:tokenA, :tokenB, :tokenX].each do |token|
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
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "addLiquidity",
          args: {
            tokenA: token_a_address,
            tokenB: token_x_address,
            amountADesired: amountADesired,
            amountBDesired: amountBDesired,
            amountAMin: 0,
            amountBMin: 0,
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "addLiquidity",
          args: {
            tokenA: token_b_address,
            tokenB: token_x_address,
            amountADesired: amountADesired,
            amountBDesired: amountBDesired,
            amountAMin: 0,
            amountBMin: 0,
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
    
    token_locker_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: nil,
        data: {
          type: "FacetSwapV1Locker",
          args: { _facetSwapFactory: factory_address }
        }
      }
    )
    
    token_locker_address = token_locker_deploy_receipt.address
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: pair_address,
        data: {
          function: "approve",
          args: {
            spender: token_locker_address,
            amount: (2 ** 256 - 1)
          }
        }
      }
    )
    
    unlockDate = 30.days.from_now.to_i
    amountToLock = 1000
    
    lock_token_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_locker_address,
        data: {
          function: "lockLPToken",
          args: {
            lpToken: pair_address,
            amount: amountToLock,
            unlockDate: unlockDate,
            withdrawer: user_address
          }
        }
      }
    )
    
    lockDate = lock_token_receipt.logs.detect{|i| i['event'] == 'Deposit'}['data']['lockDate']
    
    token_lock = ContractTransaction.make_static_call(
      contract: token_locker_address,
      function_name: "tokenLocks",
      function_args: 1
    )
    
    expect(token_lock).to eq({
      lpToken: pair_address,
      lockDate: lockDate,
      amount: amountToLock,
      unlockDate: unlockDate,
      lockId: 1,
      owner: user_address,
    }.with_indifferent_access)
    
    expect(ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: token_locker_address
    )).to eq(amountToLock)
    
    lock_token_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_locker_address,
        data: {
          function: "lockLPToken",
          args: {
            lpToken: pair_address,
            amount: amountToLock * 2,
            unlockDate: unlockDate,
            withdrawer: user_address
          }
        }
      }
    )
    
    lockDate = lock_token_receipt.logs.detect{|i| i['event'] == 'Deposit'}['data']['lockDate']

    token_lock = ContractTransaction.make_static_call(
      contract: token_locker_address,
      function_name: "tokenLocks",
      function_args: 2
    )
    
    expect(token_lock).to eq({
      lpToken: pair_address,
      lockDate: lockDate,
      amount: amountToLock * 2,
      unlockDate: unlockDate,
      lockId: 2,
      owner: user_address,
    }.with_indifferent_access)

    travel_to Time.now + 31.days

    lp_balance_before_withdraw = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    # Call withdraw function
    withdraw_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_locker_address,
        data: {
          function: "withdraw",
          args: {
            lockId: 1,
            amount: amountToLock
          }
        }
      }
    )

    expect(ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: token_locker_address
    )).to eq(amountToLock * 2)
    
    # Check that the TokenLock was updated correctly
    token_lock = ContractTransaction.make_static_call(
      contract: token_locker_address,
      function_name: "tokenLocks",
      function_args: 1
    )

    expect(token_lock).to eq({
      lpToken: "0x0000000000000000000000000000000000000000",
      lockDate: 0,
      amount: 0,
      unlockDate: 0,
      lockId: 0,
      owner: "0x0000000000000000000000000000000000000000",
    }.with_indifferent_access)

    # Check that the correct amount of tokens was transferred from the contract to the user
    lp_balance_after_withdraw = ContractTransaction.make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    expect(lp_balance_after_withdraw - lp_balance_before_withdraw).to eq(amountToLock)
    
    travel_to Time.now + 31.days
    
    old_unlock_date = token_lock['unlockDate']
    
    relock_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_locker_address,
        data: {
          function: "relock",
          args: {
            lockId: 2,
            unlockDate: 1.year.from_now.to_i
          }
        }
      }
    )

    # Check that the TokenLock was updated correctly
    token_lock = ContractTransaction.make_static_call(
      contract: token_locker_address,
      function_name: "tokenLocks",
      function_args: 2
    )

    expect(token_lock['amount']).to eq(amountToLock * 2)
    expect(token_lock['unlockDate']).to eq(1.year.from_now.to_i)
    
    in_block do |c|
      c.trigger_contract_interaction_and_expect_error(
        error_msg_includes: "Unlock time must be in the future",
        from: user_address,
        payload: {
          to: token_locker_address,
          data: {
            function: "relock",
            args: {
              lockId: 2,
              unlockDate: 1.day.ago.to_i
            }
          }
        }
      )
      
      c.trigger_contract_interaction_and_expect_error(
        error_msg_includes: "Tokens are still locked",
        from: user_address,
        payload: {
          to: token_locker_address,
          data: {
            function: "withdraw",
            args: {
              lockId: 2,
              amount: amountToLock
            }
          }
        }
      )
    end
    
    travel_to Time.now + 1.year + 1.day
    
    withdraw_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_locker_address,
        data: {
          function: "withdraw",
          args: {
            lockId: 2,
            amount: amountToLock
          }
        }
      }
    )
    
    token_lock = ContractTransaction.make_static_call(
      contract: token_locker_address,
      function_name: "tokenLocks",
      function_args: 2
    )

    expect(token_lock['amount']).to eq(amountToLock)
    
    withdraw_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_locker_address,
        data: {
          function: "withdraw",
          args: {
            lockId: 2,
            amount: amountToLock
          }
        }
      }
    )
    
    token_lock = ContractTransaction.make_static_call(
      contract: token_locker_address,
      function_name: "tokenLocks",
      function_args: 2
    )

    expect(token_lock['lockId']).to eq(0)
  end
end
