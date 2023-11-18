require 'rails_helper'

describe 'On Change and State Proxy Dirty Tracking' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  
  before(:all) do
    update_supported_contracts("TestOnChange")
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
        function_name: "staticCallShouldFail",
      )
    }.to raise_error(Contract::StaticCallError)
    
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
      }.to raise_error(Contract::StaticCallError)
    end
    
    (1..4).each do |i|
      expect {
        ContractTransaction.make_static_call(
          contract: tester.effective_contract_address,
          function_name: "arrayFail#{i}",
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    expect {
      ContractTransaction.make_static_call(
        contract: tester.effective_contract_address,
        function_name: "staticCallAttemptModifySymbol",
      )
    }.to raise_error(Contract::StaticCallError)
  end
end
