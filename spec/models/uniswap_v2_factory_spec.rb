require 'rails_helper'

RSpec.describe Contracts::UniswapV2Factory, type: :model do
  it 'creates a new pair successfully' do
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
    
    ContractTransaction.make_static_call(
      contract: factory_deploy_receipt.address,
      function_name: "allPairsLength"
    )
    
    ContractTransaction.make_static_call(
      contract: factory_deploy_receipt.address,
      function_name: "getAllPairs"
    )
    
    expect(create_pair_receipt.logs).to include(
      hash_including('event' => 'PairCreated')
    )
  end
  
  it 'throws error when creating pair with identical tokens' do
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
  
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: 'Scribeswap: IDENTICAL_ADDRESSES',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        to: factory_deploy_receipt.address,
        data: {
          function: "createPair",
          args: {
            tokenA: "0x1000000000000000000000000000000000000000",
            tokenB: "0x1000000000000000000000000000000000000000" # Same address to trigger the error
          }
        }
      }
    )
  end
  
  it 'throws error when creating pair that already exists' do
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
  
    trigger_contract_interaction_and_expect_success(
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
  
    trigger_contract_interaction_and_expect_error(
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
  end
end
