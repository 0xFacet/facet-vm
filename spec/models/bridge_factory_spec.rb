require 'rails_helper'

describe 'ERC20BridgeFactory contract' do
  let(:alice) { "0x000000000000000000000000000000000000000a" }
  let(:trusted_smart_contract) { "0x0000000000000000000000000000000000000ccc" }
  let(:token_smart_contract) { "0xccc0000000000000000000000000000000000000" }
  let(:daryl) { "0x000000000000000000000000000000000000000d" }
  
  before(:all) do
    update_supported_contracts("ERC20BridgeFactory")
    update_supported_contracts("ERC20Bridge")
  end
  
  it "has basic functionality" do
    factory = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "ERC20BridgeFactory",
          args: {
            trustedSmartContract: trusted_smart_contract
          }
        }
      }
    )
    
    bridge_in = trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: "call",
        data: {
          to: factory.address,
          function: "bridgeIn",
          args: {
            tokenSmartContract: token_smart_contract,
            decimals: 5,
            symbol: "USDC",
            name: "USD Coin",
            to: daryl,
            amount: 1.ether
          }
        }
      }
    )
    
    created_address = bridge_in.logs.detect{|i| i['event'] == 'BridgeCreated'}['data']['newBridge']
    
    daryl_initial_balance = ContractTransaction.make_static_call(
      contract: created_address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    expect(daryl_initial_balance).to eq(1.ether)
    
    bridge_in = trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: "call",
        data: {
          to: factory.address,
          function: "bridgeIn",
          args: {
            tokenSmartContract: token_smart_contract,
            decimals: 5,
            symbol: "USDC",
            name: "USD Coin",
            to: alice,
            amount: 2.ether
          }
        }
      }
    )
    
    expect(bridge_in.logs.detect{|i| i['event'] == 'BridgeCreated'}).to eq(nil)
    
    alice_initial_balance = ContractTransaction.make_static_call(
      contract: created_address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    expect(alice_initial_balance).to eq(2.ether)
    
    bridge_out = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: factory.address,
          function: "bridgeOut",
          args: {
            bridgeDumbContract: created_address,
            amount: 1.5.ether
          }
        }
      }
    )
    
    withdrawalId = bridge_out.logs.detect{|i| i['event'] == 'InitiateWithdrawal'}['data']['withdrawalId']
    
    expect(ContractTransaction.make_static_call(
      contract: created_address,
      function_name: "balanceOf",
      function_args: alice
    )).to eq(0.5.ether)
    
    mark_complete = trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: "call",
        data: {
          to: factory.address,
          function: "markWithdrawalComplete",
          args: {
            to: alice,
            withdrawalId: withdrawalId,
            tokenSmartContract: token_smart_contract
          }
        }
      }
    )
    
    expect(ContractTransaction.make_static_call(
      contract: created_address,
      function_name: "withdrawalIdAmount",
      function_args: withdrawalId
    )).to eq(0)
  end
end
