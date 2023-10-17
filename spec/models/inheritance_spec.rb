require 'rails_helper'

RSpec.describe AbiProxy, type: :model do
  before(:all) do
    RubidityFile.add_to_registry('spec/fixtures/TestContract.rubidity')
  end
  
  it "won't deploy abstract contract" do
    deploy_receipt = trigger_contract_interaction_and_expect_deploy_error(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "ERC20",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )
  end
  
  it "allows a child contract to override a parent contract's function" do
    deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "TestContract",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )

    call_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deploy_receipt.address,
        "functionName": "_mint",
        "args": {
          "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          "amount": "5"
        },
      }
    )
  end

  it "does not allow a child contract to call a parent contract's function without overriding it" do
    deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "TestContractNoOverride",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )

    trigger_contract_interaction_and_expect_call_error(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deploy_receipt.address,
        "functionName": "_mint",
        "args": {
          "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          "amount": "5"
        },
      }
    )
  end
  
  it "allows a child contract to override a parent contract's function and call the parent contract's function using the _PARENT prefix" do
    deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "TestContractMultipleInheritance",
        "constructorArgs": {
          "name": "Test Token",
          "symbol": "TT",
          "decimals": 18
        },
      }
    )
  
    call_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deploy_receipt.address,
        "functionName": "_mint",
        "args": {
          "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
          "amount": "5"
        },
      }
    )
    
    expect(call_receipt.logs.map{|i| i['event']}.sort)
    .to eq(['Greet', 'Transfer', 'Transfer'].sort)
    
    expect(call_receipt.contract.latest_state['totalSupply']).to eq(10)
    
    expect(call_receipt.contract.latest_state.
      slice('definedHere', 'definedInTest', 'definedInNonToken').values.sort).to eq(
        ['definedHere', 'definedInTest', 'definedInNonToken'].sort
      )
  end
  
  it "raises an error when declaring override without overriding anything" do
    expect {
      RubidityFile.add_to_registry('spec/fixtures/TestContractOverrideNonVirtual2.rubidity')
    }.to raise_error(ContractErrors::InvalidOverrideError)
  end
  
  it "raises an error when trying to override a non-virtual function" do
    expect {
      RubidityFile.add_to_registry('spec/fixtures/TestContractOverrideNonVirtual.rubidity')
    }.to raise_error(ContractErrors::InvalidOverrideError)
  end
  
  it "raises an error when trying to override a virtual function without the override modifier" do
    expect {
      RubidityFile.add_to_registry('spec/fixtures/TestContractOverrideWithoutModifier.rubidity')
    }.to raise_error(ContractErrors::InvalidOverrideError)
  end
  
  it "raises an error when defining the same function twice in a contract" do
    expect {
      RubidityFile.add_to_registry('spec/fixtures/TestContractDuplicateFunction.rubidity')
    }.to raise_error(ContractErrors::FunctionAlreadyDefinedError)
  end
end
