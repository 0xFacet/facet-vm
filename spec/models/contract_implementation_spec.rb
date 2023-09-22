require 'rails_helper'

class Contracts::ERC20Receiver < ContractImplementation
  is :ERC20
  
  constructor() {
    ERC20.constructor(name: "bye", symbol: "B", decimals: 18)
  }
end

class Contracts::ERC20Minimal < ContractImplementation
  is :ERC20
  
  constructor(name: :string, symbol: :string, decimals: :uint8) {
    ERC20.constructor(name, symbol, decimals)
  }
end

class Contracts::AddressArg < ContractImplementation
  event :SayHi, { sender: :address }
  event :Responded, { response: :string }
  
  constructor(testAddress: :address) {
    emit :SayHi, sender: testAddress
  }
  
  function :respond, { greeting: :string }, :public do
    emit :Responded, response: (greeting + " back")
  end
end

class Contracts::Receiver < ContractImplementation
  event :MsgSender, { sender: :address }
  
  constructor() {}
  
  function :sayHi, {}, :public, :view, returns: :string do
    return "hi"
  end
  
  function :receiveCall, { }, :public, returns: :uint256 do
    emit :MsgSender, sender: msg.sender
    
    return block.number
  end
  
  function :internalCall, { }, :internal do
  end
  
  function :name, {}, :public, :view, returns: :string do
    return "hi"
  end
end

class Contracts::Caller < ContractImplementation
  event :BlockNumber, { number: :uint256 }
  
  constructor() {}
  
  function :makeCall, { receiver: :address }, :public, returns: :string do
    resp = Receiver(receiver).receiveCall()
    
    emit :BlockNumber, number: block.number
    emit :BlockNumber, number: resp
    
    return Receiver(receiver).sayHi()
  end
  
  function :callInternal, { receiver: :address }, :public do
    Receiver(receiver).internalCall()
  end
  
  function :testImplements, { receiver: :address }, :public, returns: :string do
    ERC20(receiver).name()
  end
end

class Contracts::Deployer < ContractImplementation
  event :ReceiverCreated, { contract: :address }
  event :ContractCreated, { contract: :address }

  constructor() {}
  
  function :createReceiver, { name: :string, symbol: :string, decimals: :uint256 }, :public, returns: :address do
    erc20 = new ERC20Minimal(name, symbol, decimals)
    
    emit :ReceiverCreated, contract: erc20.address
    
    return erc20.address
  end

  function :createMalformedReceiver, { name: :string }, :public, returns: :address do
    erc20 = new ERC20Minimal(name)

    emit :ReceiverCreated, contract: erc20.address
    
    return erc20.address
  end
  
  function :createAddressArgContract, { testAddress: :address }, :public, returns: :address do
    contract = new AddressArg(testAddress)

    emit :ReceiverCreated, contract: contract.address

    return contract.address
  end
  
  function :createAddressArgContractAndRespond, { testAddress: :address, greeting: :string }, :public do
    contract = new AddressArg(testAddress)
    emit :ReceiverCreated, contract: contract.address
    contract.respond(greeting)
  end
  
  function :createERC20Minimal, { name: :string, symbol: :string, decimals: :uint256 }, :public, returns: :address do
    contract = new ERC20Minimal(name, symbol, decimals)
    
    emit :ContractCreated, contract: contract.address
    
    return contract.address
  end
  
  function :callRespond, { contract_address: :address, greeting: :string }, :public do
    contract = AddressArg(contract_address)
    contract.respond(greeting)
  end
end

class Contracts::MultiDeployer < ContractImplementation
  constructor() {}

  function :deployContracts, { deployerAddress: :address }, :public, returns: :address do
    contract = new CallerTwo(deployerAddress)
    
    testNoArgs = new MultiDeployer()
    
    contract.callDeployer()
  end
end

class Contracts::CallerTwo < ContractImplementation
  address :deployerAddress
  
  constructor(deployerAddress: :address) {
    s.deployerAddress = deployerAddress
  }
  
  function :callDeployer, {}, :public, returns: :address do
    deployer = Deployer(s.deployerAddress)

    deployer.createERC20Minimal("myToken", "MTK", 18)
  end
end

RSpec.describe ContractImplementation, type: :model do
  it "sets msg.sender correctly when one contract calls another" do
    caller_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Caller",
        "constructorArgs": {},
      }
    )

    receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Receiver",
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
    
    last_call = call_receipt.contract_transaction.contract_calls.last
    
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
        "protocol": "Caller",
        "constructorArgs": {},
      }
    )
    
    erc20_receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "ERC20Receiver",
        "constructorArgs": {},
      }
    )
    
    receiver_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Receiver",
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
  
    trigger_contract_interaction_and_expect_call_error(
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
        "protocol": "Deployer",
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
        "protocol": "Deployer",
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
        "protocol": "ERC20Minimal",
        "constructorArgs": ["name", 'symbol', 10],
      }
    )
  
    # Now we deploy the Deployer contract
    deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "Deployer",
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
        "protocol": "Deployer",
        "constructorArgs": {},
      }
    )

    # then deploy the MultiDeployer
    multi_deployer_deploy_receipt = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "MultiDeployer",
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
