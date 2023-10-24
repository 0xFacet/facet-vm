require 'rails_helper'

describe 'Upgrading Contracts' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }

  before(:all) do
    RubidityFile.add_to_registry('spec/fixtures/UpgradeableTest.rubidity')
  end
  
  it 'is upgradeable' do
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UpgradeableV1"
        }
      }
    )
    
    hi_result = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "sayHi",
      function_args: "Rubidity"
    )
    
    expect(hi_result).to eq("Hello Rubidity")
    
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    
    expect(version).to eq(1)

    hash = RubidityFile.registry.detect{|k, v| v.name == "UpgradeableV2"}.first
    
    upgrade_tx = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: v1.contract_address,
        data: {
          function: "upgradeFromV1",
          args: "0x" + hash
        }
      }
    )
    
    v1_log = upgrade_tx.logs.detect do |i|
      i['event'] == 'NotifyOfVersion' && i['data']['from'] == "v1"
    end
    
    v2_log = upgrade_tx.logs.detect do |i|
      i['event'] == 'NotifyOfVersion' && i['data']['from'] == "v2"
    end
    
    expect(v1_log['data']['version']).to eq(2)
    expect(v2_log['data']['version']).to eq(2)
    
    hi_result = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "sayHi",
      function_args: "Rubidity"
    )
    
    expect(hi_result).to eq("Greetings Rubidity")
    
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    
    expect(version).to eq(2)
  end
  
  it 'deals with infinite loop' do
    d1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        data: {
          type: "callStackDepth1"
        }
      }
    )
    
    d2 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        data: {
          type: "callStackDepth2"
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      from: user_address,
      payload: {
        to: d2.contract_address,
        data: {
          function: "callOtherContract",
          args: d1.contract_address
        }
      }
    )
  end
  
  it 'upgrades itself' do
    # v1 = trigger_contract_interaction_and_expect_success(
    #   from: user_address,
    #   payload: {
    #     to: nil,
    #     data: {
    #       type: "UpgradeableV1"
    #     }
    #   }
    # )
  end
end
