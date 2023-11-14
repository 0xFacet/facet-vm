require 'rails_helper'

RSpec.describe ContractCall, type: :model do
  let(:from_address) { '0xc2172a6315c1d7f6855768f843c420ebb36eda97' }

  before(:all) do
    update_contract_allow_list("UniswapV2Pair", "StubERC20B")
  end
  
  it 'calculates eoa_nonce correctly' do
    receipt = trigger_contract_interaction_and_expect_success(
      from: from_address,
      payload: {
        to: nil,
        data: {
          type: "StubERC20B"
        }
      }
    )
    
    deployed = receipt.contract_address

    trigger_contract_interaction_and_expect_success(
      from: from_address,
      payload: {
        to: deployed, # Replace with actual contract address
        data: {
          function: "approve",
          args: {
            spender: from_address, # Replace with actual spender address
            amount: (2 ** 256 - 1)
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_error(
      from: from_address,
      payload: {
        to: deployed, # Replace with actual contract address
        data: {
          function: "approve",
          args: {
            spender: from_address, # Replace with actual spender address
            amount: "AA"
          }
        }
      }
    )
    
    contract_call = ContractCall.new(from_address: from_address)
    expect(contract_call.eoa_nonce).to eq(3)
  end
  
  it 'calculates contract_nonce correctly' do
    factory_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: nil,
        data: {
          type: "UniswapV2Factory",
          args: { _feeToSetter: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97" }
        }
      }
    )
  
    factory_address = factory_deploy_receipt.contract_address
    
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: factory_deploy_receipt.address,
        data: {
          function: "createPair",
          args: {
            tokenA: "0x1000000000000000000000000000000000000000", 
            tokenB: "0x2000000000000000000000000000000000000000"
          }
        }
      }
    )
    
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: factory_deploy_receipt.address,
        data: {
          function: "createPair",
          args: {
            tokenA: "0x4000000000000000000000000000000000000000", 
            tokenB: "0x5000000000000000000000000000000000000000"
          }
        }
      }
    )
    
    create_pair_receipt = trigger_contract_interaction_and_expect_error(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: factory_deploy_receipt.address,
        data: {
          function: "createPair",
          args: {
            tokenA: "zz", 
            tokenB: "0x5000000000000000000000000000000000000000"
          }
        }
      }
    )
    
    test_call = ContractCall.new(from_address: factory_address)
    
    contract_transaction = ContractTransaction.new
    
    contract_transaction.contract_calls = [test_call]
    
    test_call.contract_transaction = contract_transaction
    
    expect(test_call.contract_nonce).to eq(2)
  end
  
  it 'fails on read only write' do
    receipt = trigger_contract_interaction_and_expect_success(
      from: from_address,
      payload: {
        to: nil,
        data: {
          type: "StubERC20B"
        }
      }
    )
    
    deployed = receipt.contract_address
    
    expect {
      ContractTransaction.make_static_call(
        contract: deployed,
        function_name: "unsafeReadOnly"
      )
    }.to raise_error(Contract::StaticCallError)
    
    trigger_contract_interaction_and_expect_error(
      from: from_address,
      payload: {
        to: deployed,
        data: {
          function: "callOwnUnsafeReadOnly"
        }
      }
    )
  end
end
