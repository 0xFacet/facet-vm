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
      # 'FacetSwapV1RouterWithRewards',
      'FacetSwapV1FactoryVariableFee',
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
          type: "FacetSwapV1FactoryVariableFee",
          args: {
            _feeToSetter: user_address
          }
        }
      }
    )
    factory_address = factory_deploy_receipt.address
    
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: factory_address,
        data: {
          function: "setFeeTo",
          args: {
            _feeTo: frank
          }
        }
      }
    )

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
          type: "FacetSwapV1Router",
          args: {
            _factory: factory_address,
            _WETH: weth_address
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
  end
end
