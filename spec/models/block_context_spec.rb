require 'rails_helper'

describe 'BlockContext' do
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:daryl) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:trusted_smart_contract) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let(:max_supply) { 10000 }
  let(:base_uri) { "https://example.com/" }
  let(:name) { "TestNFT" }
  let(:symbol) { "TNFT" }
  let(:fee) { (0.0005.to_d * 1.ether).to_i }
  let(:fee_to_address) { "0xf00000000000000000000000000000000000000f" }
  let(:per_mint_fee) { (0.0005.to_d * 1.ether).to_i }
  
  before(:all) do
    update_supported_contracts("OpenEditionERC721")
    update_supported_contracts("TestBlockContext")
  end
  
  it "does things" do
    contract = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "TestBlockContext",
          args: {}
        }
      }
    )
    
    target = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "TestBlockContext",
          args: {}
        }
      }
    )
    
    in_block do |c|
      c.trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: :call,
          data: {
            to: target.address,
            function: "changeVar1",
            args: [5, false]
          }
        }
      )
      
      c.trigger_contract_interaction_and_expect_error(
        from: alice,
        payload: {
          op: :call,
          data: {
            to: contract.address,
            function: "oneSuccessOneRevert",
            args: [target.address, 10]
          }
        }
      )
    end
    
    ts = ContractTransaction.make_static_call(
      contract: target.address,
      function_name: "var1",
      function_args: {}
    )
    
    expect(ts).to eq(5)
    # binding.pry
    # exit

    nft = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "OpenEditionERC721",
          args: {
            name: "name",
            symbol: "symbol",
            contentURI: "",
            maxPerAddress: 10,
            description: "description",
            mintStart: 1,
            mintEnd: (Time.current + 100.years).to_i
          }
        }
      }
    )
    
    txs = in_block do |c|
      c.trigger_contract_interaction_and_expect_success(
        from: bob,
        payload: {
          op: :call,
          data: {
            to: nft.address,
            function: "mint",
            args: 2
          }
        }
      )

      c.trigger_contract_interaction_and_expect_error(
        from: alice,
        payload: {
          op: :call,
          data: {
            to: nft.address,
            function: "mint",
            args: 11
          }
        }
      )
      
      c.trigger_contract_interaction_and_expect_success(
        from: daryl,
        payload: {
          op: :call,
          data: {
            to: nft.address,
            function: "mint",
            args: 5
          }
        }
      )
    end
    
    log_indexes = txs.flat_map{|i| i['logs'].map{|j| j['log_index']}}
    logs_count = txs.flat_map{|i| i['logs']}.count
    
    expect(log_indexes).to eq((0...logs_count).to_a)
    
    ts = ContractTransaction.make_static_call(
      contract: nft.address,
      function_name: "totalSupply",
      function_args: {}
    )
    
    expect(ts).to eq(7)
  end
end
