require 'rails_helper'

describe 'Upgrading Contracts' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }

  before(:all) do
    ContractArtifact.create_artifacts_from_files('spec/fixtures/UpgradeableTest.rubidity')
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

    hash = ContractArtifact.class_from_name("UpgradeableV2").init_code_hash
    
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
  
  it 'rejects unauthorized upgrades' do
    # Deploy the initial version of the contract by a user
    v1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "UpgradeableV1"
        }
      }
    )
  
    # Attempt to upgrade the contract from an unauthorized address
    unauthorized_address = "0x0000000000000000000000000000000000000001"
  
    # This should fail, hence expect_error
    trigger_contract_interaction_and_expect_error(
      from: unauthorized_address,
      payload: {
        to: v1.contract_address,
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
          type: "UpgradeableV1"
        }
      }
    )
  
    # Attempt to upgrade the contract with an incorrect version hash
    incorrect_hash = "0x0000000000000000000000000000000000000000000000000000000000000000"
  
    # This should fail, hence expect_error
    trigger_contract_interaction_and_expect_error(
      from: user_address,
      payload: {
        to: v1.contract_address,
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
          type: "MaliciousReentrancy"
        }
      }
    )
  
    # Attempt to perform a re-entrancy attack via the malicious contract
    # Assuming that the hash used here is valid
    valid_hash = ContractArtifact.class_from_name("UpgradeableV2").init_code_hash
  
    # This should fail, hence expect_error
    trigger_contract_interaction_and_expect_error(
      from: user_address,
      payload: {
        to: malicious.contract_address,
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
          type: "UpgradeableV1"
        }
      }
    )
  
    # Upgrade to v2
    hash_v2 = ContractArtifact.class_from_name("UpgradeableV2").init_code_hash
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: v1.contract_address,
        data: {
          function: "upgradeFromV1",
          args: "0x" + hash_v2
        }
      }
    )
  
    version = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "version",
    )
    expect(version).to eq(2)
  
    # Upgrade to v3
    hash_v3 = ContractArtifact.class_from_name("UpgradeableV3").init_code_hash
    
    # First fail
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Upgrade error',
      from: user_address,
      payload: {
        to: v1.contract_address,
        data: {
          function: "upgradeAndRevert",  # Assuming you have a similar function in V2 for further upgrades
          args: "0x" + hash_v3
        }
      }
    )
    
    lastUpgradeHash = ContractTransaction.make_static_call(
      contract: v1.address,
      function_name: "lastUpgradeHash",
    )
    expect(lastUpgradeHash).to eq("0x" + hash_v2)
    
    expect(Contract.find_by_address(v1.contract_address).current_init_code_hash).to eq(hash_v2)
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: v1.contract_address,
        data: {
          function: "upgradeFromV2",  # Assuming you have a similar function in V2 for further upgrades
          args: "0x" + hash_v3
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
          type: "NotUpgradeable"
        }
      }
    )
  
    hash_v2 = ContractArtifact.class_from_name("UpgradeableV2").init_code_hash
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Contract is not upgradeable',
      from: user_address,
      payload: {
        to: v1.contract_address,
        data: {
          function: "upgradeFromV1",
          args: "0x" + hash_v2
        }
      }
    )
  end
  
  it 'handles complex upgrade chain correctly' do
# Deploy A1 and B1 as before
    a1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "A1"
        }
      }
    )

    b1 = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "B1"
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
    hash_a2 = ContractArtifact.class_from_name("A2").init_code_hash

    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: a1.address,
        data: {
          function: "setNextUpgradeHash",
          args: "0x" + hash_a2
        }
      }
    )

    hash_b2 = ContractArtifact.class_from_name("B2").init_code_hash

    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: b1.address,
        data: {
          function: "setNextUpgradeHash",
          args: "0x" + hash_b2
        }
      }
    )

    # Trigger the complex upgrade chain
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: a1.contract_address,
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
