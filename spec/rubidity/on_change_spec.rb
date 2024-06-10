require 'rails_helper'

describe 'On Change and State Proxy Dirty Tracking' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  
  before(:all) do
    update_supported_contracts("TestOnChange", "StubERC20")
  end
  
  it 'does a basic static call' do
    tester = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: { data: { type: "TestOnChange" } }
    )
    
    expect {
      ContractTransaction.make_static_call(
        contract: tester.effective_contract_address,
        function_name: "staticCallShouldSucceed",
      )
    }.not_to raise_error
    
    expect {
      ContractTransaction.make_static_call(
        contract: tester.effective_contract_address,
        function_name: "boolFail",
      )
    }.to raise_error(/Invalid change in read-only context/)
    
    expect {
      ContractTransaction.make_static_call(
        contract: tester.effective_contract_address,
        function_name: "staticCallShouldFail",
      )
    }.to raise_error(/Invalid change in read-only context/)
    
    (1..2).each do |i|
      expect {
        ContractTransaction.make_static_call(
          contract: tester.effective_contract_address,
          function_name: "arraySucceed#{i}",
        )
      }.not_to raise_error
    end
    
    (1..2).each do |i|
      expect {
        ContractTransaction.make_static_call(
          contract: tester.effective_contract_address,
          function_name: "mappingSucceed#{i}",
        )
      }.not_to raise_error
    end
    
    (1..5).each do |i|
      expect {
        ContractTransaction.make_static_call(
          contract: tester.effective_contract_address,
          function_name: "mappingFail#{i}",
        )
      }.to raise_error(/Invalid change in read-only context/)
    end
    
    (1..4).each do |i|
      expect {
        ContractTransaction.make_static_call(
          contract: tester.effective_contract_address,
          function_name: "arrayFail#{i}",
        )
      }.to raise_error(/Invalid change in read-only context/)
    end
    
    expect {
      ContractTransaction.make_static_call(
        contract: tester.effective_contract_address,
        function_name: "emptyNonView",
      )
    }.to raise_error(/Cannot call non-read-only function in static call/)
    
    expect {
      ContractTransaction.make_static_call(
        contract: tester.effective_contract_address,
        function_name: "staticCallAttemptModifySymbol",
      )
    }.to raise_error(/Invalid change in read-only context/)
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Invalid change in read-only context',
      from: user_address,
      payload: {
        to: tester.effective_contract_address,
        data: {
          function: "pushPerson",
          args: {
            newPerson: {
              name: "Alice",
              age: 20
            }
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Invalid change in read-only context',
      from: user_address,
      payload: {
        to: tester.effective_contract_address,
        data: {
          function: "chain1"
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: tester.effective_contract_address,
        data: {
          function: "deploySelfCopy",
        }
      }
    )
    
    [:readOnlyContext, :readOnlyContext2,
      :readOnlyContext0, :readOnlyContext1,
      :readOnlyCreate, :readOnlyCall, :readOnlyUpgrade].each do |fn|
      expect {
        ContractTransaction.make_static_call(
          contract: tester.effective_contract_address,
          function_name: fn,
        )
      }.to raise_error(/Invalid change in read-only context/)
    end
  end
end
