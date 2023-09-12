require 'rails_helper'

class Contracts::ERC20Receiver < ContractImplementation
  is :ERC20
  
  constructor() {
    ERC20.constructor(name: "bye", symbol: "B", decimals: 18)
  }
end

class Contracts::Receiver < ContractImplementation
  event :MsgSender, { sender: :address }
  
  constructor() {}
  
  function :sayHi, {}, :public, :view do
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
  
  function :testImplements, { receiver: :address }, :public do
    ERC20(receiver).name()
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
end
