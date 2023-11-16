require 'rails_helper'

describe 'Upgrading Contracts' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }

  before(:all) do
    hashes = RubidityTranspiler.transpile_file("UpgradeableTest").map(&:init_code_hash)
    ContractTestHelper.update_contract_allow_list(hashes)
  end
  
  it 'is upgradeable' do
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UpgradeableV1:UpgradeableTest"
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

    v2 = RubidityTranspiler.transpile_and_get("UpgradeableV2:UpgradeableTest")

    upgrade_tx = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeFromV1",
          args: [v2.init_code_hash, v2.source_code]
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
          type: "callStackDepth1:UpgradeableTest"
        }
      }
    )
    
    d2 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        data: {
          type: "callStackDepth2:UpgradeableTest"
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      from: user_address,
      payload: {
        to: d2.effective_contract_address,
        data: {
          function: "callOtherContract",
          args: d1.effective_contract_address
        }
      }
    )
  end
  
  it 'rejects unauthorized upgrades' do
    # Deploy the initial version of the contract by a user
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UpgradeableV1:UpgradeableTest"
        }
      }
    )
  
    # Attempt to upgrade the contract from an unauthorized address
    unauthorized_address = "0x0000000000000000000000000000000000000001"
  
    # This should fail, hence expect_error
    trigger_contract_interaction_and_expect_error(
      from: unauthorized_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeFromV1",
          args: "0xSomeHash"
        }
      }
    )
  
    # Confirm that the contract version has not changed
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    
    expect(version).to eq(1)
  end
  
  it 'handles incorrect version hash gracefully' do
    # Deploy the initial version of the contract
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UpgradeableV1:UpgradeableTest"
        }
      }
    )
  
    # Attempt to upgrade the contract with an incorrect version hash
    incorrect_hash = "0x0000000000000000000000000000000000000000000000000000000000000000"
  
    # This should fail, hence expect_error
    trigger_contract_interaction_and_expect_error(
      from: user_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeFromV1",
          args: incorrect_hash
        }
      }
    )
  
    # Confirm that the contract version has not changed
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    
    expect(version).to eq(1)
  end
  
  it 'prevents re-entrancy attacks' do
    # Deploy the initial version of the malicious contract
    malicious = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "MaliciousReentrancy:UpgradeableTest"
        }
      }
    )
  
    # Attempt to perform a re-entrancy attack via the malicious contract
    # Assuming that the hash used here is valid
    v2 = RubidityTranspiler.transpile_and_get("UpgradeableV2:UpgradeableTest")
    valid_hash = v2.init_code_hash
  
    # This should fail, hence expect_error
    trigger_contract_interaction_and_expect_error(
      from: user_address,
      payload: {
        to: malicious.effective_contract_address,
        data: {
          function: "attemptReentrancy",
          args: valid_hash
        }
      }
    )
  
    # Confirm that the contract version has not changed
    version = ContractTransaction.make_static_call(
      contract: malicious.address,
      function_name: "version",
    )
    
    expect(version).to eq(1)
  
    # Confirm that re-entrancy was indeed triggered but prevented
    re_entrancy_triggered = ContractTransaction.make_static_call(
      contract: malicious.address,
      function_name: "reEntrancyTriggered",
    )
    
    expect(re_entrancy_triggered).to eq(false)
  end
  
  it 'handles multiple upgrades correctly' do
    # Deploy the initial version of the contract
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UpgradeableV1:UpgradeableTest"
        }
      }
    )
  
    # Upgrade to v2
    v2 = RubidityTranspiler.transpile_and_get("UpgradeableV2:UpgradeableTest")
    hash_v2 = v2.init_code_hash
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeFromV1",
          args: [hash_v2, v2.source_code]
        }
      }
    )
  
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    expect(version).to eq(2)
  
    # Upgrade to v3
    v3 = RubidityTranspiler.transpile_and_get("UpgradeableV3:UpgradeableTest")
    hash_v3 = v3.init_code_hash
    
    # First fail
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Upgrade error',
      from: user_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeAndRevert",  # Assuming you have a similar function in V2 for further upgrades
          args: [hash_v3, v3.source_code]
        }
      }
    )
    
    lastUpgradeHash = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "lastUpgradeHash",
    )
    expect(lastUpgradeHash).to eq(hash_v2)
    
    expect(Contract.find_by_address(v1.effective_contract_address).current_init_code_hash).to eq(hash_v2)
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeFromV2",  # Assuming you have a similar function in V2 for further upgrades
          args: [hash_v3, v3.source_code]
        }
      }
    )
  
    # Confirm that the version is now 3
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    expect(version).to eq(3)
    
    hi_result = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "sayHi",
      function_args: "Contract"
    )
    
    expect(hi_result).to eq("I am V3 Contract")
  end
  
  it 'handles non-upgradeable correctly' do
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        data: {
          type: "NotUpgradeable:UpgradeableTest"
        }
      }
    )
  
    v2 = RubidityTranspiler.transpile_and_get("UpgradeableV2:UpgradeableTest")
    hash_v2 = v2.init_code_hash
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Contract is not upgradeable',
      from: user_address,
      payload: {
        to: v1.effective_contract_address,
        data: {
          function: "upgradeFromV1",
          args: [hash_v2, v2.source_code]
        }
      }
    )
  end
  
  it 'handles complex upgrade chain correctly' do
# Deploy A1 and B1 as before

    # binding.pry
    a1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "A1:UpgradeableTest"
        }
      }
    )

    b1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "B1:UpgradeableTest"
        }
      }
    )

    # Set related contracts for A1 and B1
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: a1.address,
        data: {
          function: "setRelatedB",
          args: b1.address
        }
      }
    )

    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: b1.address,
        data: {
          function: "setRelatedA",
          args: a1.address
        }
      }
    )

    # Set the next upgrade hash for A1 and B1
    # Assume hash_a2 and hash_b2 are the calculated hashes for A2 and B2
    a2 = RubidityTranspiler.transpile_and_get("A2:UpgradeableTest")
    hash_a2 = a2.init_code_hash

    # binding.pry
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: a1.address,
        data: {
          function: "setNextUpgradeHash",
          args: [hash_a2, a2.source_code]
        }
      }
    )
    
    b2 = RubidityTranspiler.transpile_and_get("B2:UpgradeableTest")
    hash_b2 = b2.init_code_hash

    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: b1.address,
        data: {
          function: "setNextUpgradeHash",
          args: [hash_b2, b2.source_code]
        }
      }
    )

    # Trigger the complex upgrade chain
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: a1.effective_contract_address,
        data: {
          function: "triggerChain"
        }
      }
    )

    version_a = ContractTransaction.make_static_call(
      contract: a1.address,
      function_name: "version",
    )
    
    version_b = ContractTransaction.make_static_call(
      contract: b1.address,
      function_name: "bVersion",
    )
    
    expect(version_a).to eq(3)
    expect(version_b).to eq(2)
  end
end
