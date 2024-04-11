require 'rails_helper'

describe 'Simulate with state' do
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  
  it 'simulates' do
    contract = RubidityTranspiler.transpile_and_get("PublicMintERC20")

    resp = ContractTransaction.simulate_transaction_with_state(
      from: alice,
      tx_payload: {
        op: :create,
        data: {
          source_code: contract.source_code,
          init_code_hash: contract.init_code_hash,
          args: {
            name: "Public Mint ERC20",
            symbol: "PMINT",
            maxSupply: 1000000000000000000000000000,
            perMintLimit: 1000000000000000000000000,
            decimals: 18
          }
        }
      }
    )
    
    deployed_address = resp[:transaction_receipt]['effective_contract_address']
    
    expect(resp[:transaction_receipt][:status]).to eq('success')
    
    expect(resp[:state][:contracts].length).to eq(1)
    expect(resp[:state][:contracts].first['current_state']).to eq(
          {
            "name" => "Public Mint ERC20",
          "symbol" => "PMINT",
        "decimals" => 18,
    "totalSupply" => 0,
      "balanceOf" => {},
      "allowance" => {},
      "maxSupply" => 1000000000000000000000000000,
    "perMintLimit" => 1000000000000000000000000
          }
    )
    {      from: alice,
      tx_payload: {
        op: :call,
        data: {
          to: deployed_address,
          function: 'mint',
          args: 100
        }
      },
      initial_state: resp[:state]}.to_json.pbcopy
    exit
    resp = ContractTransaction.simulate_transaction_with_state(
      from: alice,
      tx_payload: {
        op: :call,
        data: {
          to: deployed_address,
          function: 'mint',
          args: 100
        }
      },
      initial_state: resp[:state]
    )
    
    expect(resp[:transaction_receipt][:status]).to eq('success')

    expect(resp[:state][:contracts].first['current_state']['balanceOf'][alice]).to eq(100)
    
    resp = ContractTransaction.simulate_transaction_with_state(
      from: bob,
      tx_payload: {
        op: :call,
        data: {
          to: deployed_address,
          function: 'mint',
          args: 234234234
        }
      },
      initial_state: resp[:state]
    )
    
    expect(resp[:transaction_receipt][:status]).to eq('success')

    expect(resp[:state][:contracts].first['current_state']['balanceOf'][bob]).to eq(234234234)
    expect(resp[:state][:contracts].first['current_state']['totalSupply']).to eq(234234234 + 100)
    
    expect(Contract.count).to eq(0)
  end
end
