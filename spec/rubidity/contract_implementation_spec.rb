require 'rails_helper'

RSpec.describe ContractImplementation, type: :model do
  before(:all) do
    hashes = RubidityTranspiler.transpile_file("ERC20Receiver").map(&:init_code_hash)
    
    ContractTestHelper.update_supported_contracts(*hashes)
  end
  
  it "sets msg.sender correctly when one contract calls another" do
    caller_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Caller:ERC20Receiver",
        "constructorArgs": {},
      }
    )

    receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Receiver:ERC20Receiver",
        "constructorArgs": {},
      }
    )

    call_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": caller_deploy_receipt.address,
        "functionName": "makeCall",
        "args": {
          "receiver": receiver_deploy_receipt.address,
        },
      }
    )
    
    last_call = ContractCall.where(transaction_hash: call_receipt.transaction_hash).order(:internal_transaction_index).last
    
    expect(last_call.function).to eq("sayHi")
    expect(last_call.return_value).to eq("hi")
    expect(last_call.from_address).to eq(caller_deploy_receipt.address)
    expect(last_call.to_contract_address).to eq(receiver_deploy_receipt.address)
    
    block_number_logs = call_receipt.logs.select { |log| log['event'] == 'BlockNumber' }
    expect(block_number_logs.size).to eq(2)
    expect(block_number_logs[0]['data']['number']).to eq(block_number_logs[1]['data']['number'])

    expect(call_receipt.logs).to include(
      hash_including('event' => 'MsgSender', 'data' => { 'sender' => caller_deploy_receipt.address })
    )
    
    trigger_contract_interaction_and_expect_call_error(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": caller_deploy_receipt.address,
        "functionName": "callInternal",
        "args": {
          "receiver": receiver_deploy_receipt.address,
        },
      }
    )
  end
  
  it "raises an error when trying to cast a non-ERC20 contract as ERC20" do
    caller_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Caller:ERC20Receiver",
        "constructorArgs": {},
      }
    )
    
    erc20_receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "ERC20Receiver:ERC20Receiver",
        "constructorArgs": {},
      }
    )
    
    receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Receiver:ERC20Receiver",
        "constructorArgs": {},
      }
    )
  
    trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": caller_deploy_receipt.address,
        "functionName": "testImplements",
        "args": {
          "receiver": erc20_receiver_deploy_receipt.address,
        },
      }
    )
  
    trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": caller_deploy_receipt.address,
        "functionName": "testImplements",
        "args": {
          "receiver": receiver_deploy_receipt.address,
        },
      }
    )
  end
  
  it 'creates contract from another contract' do
    deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Deployer:ERC20Receiver",
        "constructorArgs": {},
      }
    )

    receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deployer_deploy_receipt.address,
        "functionName": "createReceiver",
        "args": ["name", 'symbol', 10],
      }
    )
    
    expect(receiver_deploy_receipt.logs).to include(
      hash_including('event' => 'ReceiverCreated')
    )
  end

  it 'fails to create a contract with invalid constructor arguments' do
    deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Deployer:ERC20Receiver",
        "constructorArgs": {},
      }
    )
    
    trigger_contract_interaction_and_expect_call_error(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deployer_deploy_receipt.address,
        "functionName": "createMalformedReceiver",
        "args": {},
      }
    )
  end
  
  it 'creates contract with address argument without ambiguity' do
    # First, we deploy an arbitrary contract to get an address
    dummy_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "ERC20Minimal:ERC20Receiver",
        "constructorArgs": ["name", 'symbol', 10],
      }
    )
  
    # Now we deploy the Deployer contract
    deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Deployer:ERC20Receiver",
        "constructorArgs": {},
      }
    )
  
    # Deploy a contract where its only argument (`testAddress`) could be 
    # ambiguously interpreted as constructor parameter or a contract address
    receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deployer_deploy_receipt.address,
        "functionName": "createAddressArgContract",
        "args": [dummy_deploy_receipt.address],
      }
    )
  
    # It should still pass and create the contract successfully
    expect(receiver_deploy_receipt.logs).to include(
      hash_including('event' => 'ReceiverCreated')
    )
  
    # It should capture the testAddress in the SayHi event log
    expect(receiver_deploy_receipt.logs).to include(
      hash_including('event' => 'SayHi', 'data' => { 'sender' => dummy_deploy_receipt.address })
    )
    
    response = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": deployer_deploy_receipt.address,
        "functionName": "createAddressArgContractAndRespond",
        "args": [dummy_deploy_receipt.address, "Hello"],
      }
    )
  
    expect(response.logs).to include(
      hash_including('event' => 'ReceiverCreated')
    )
  
    expect(response.logs).to include(
      hash_including('event' => 'Responded', 'data' => {'response' => 'Hello back'})
    )
  end
  
  it 'creates and invokes contracts in complex nested operations' do
    # first, we need a Deployer that can be used by Candidate to create new tokens
    deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Deployer:ERC20Receiver",
        "constructorArgs": {},
      }
    )

    # then deploy the MultiDeployer
    multi_deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "MultiDeployer:ERC20Receiver",
      }
    )

    # call the MultiDeployer's deployContracts function, which should deploy the Caller contract
    deploy_contracts_receipt = trigger_contract_interaction_and_expect_success(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contract": multi_deployer_deploy_receipt.address,
        "functionName": "deployContracts",
        "args": deployer_deploy_receipt.address,
      }
    )

    # there should be a ContractCreated event which indicates that a new contract was created
    expect(deploy_contracts_receipt.logs).to include(
      hash_including('event' => 'ContractCreated')
    )
    
    # take the contract address from the event log
    created_erc20_address = deploy_contracts_receipt.logs.find { |l| l['event'] == 'ContractCreated' }['data']['contract']
    # binding.pry
    # verify that the created contract really is a ERC20Minimal
    # created_erc20_contract = ERC20Minimal(created_erc20_address)
    # expect(created_erc20_contract.name).to eq('myToken')
  end
end
