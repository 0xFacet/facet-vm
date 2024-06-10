require 'rails_helper'

describe 'BridgeAndCall contract' do
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:daryl) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:charlie) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let(:trusted_smart_contract) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let(:max_supply) { 10000 }
  let(:base_uri) { "https://example.com/" }
  let(:name) { "TestNFT" }
  let(:symbol) { "TNFT" }
  let(:per_mint_fee) { (0.0005.to_d * 1.ether).to_i }
  let(:fee_to_address) { "0xf00000000000000000000000000000000000000f" }

  before(:all) do
    update_supported_contracts("EtherBridge03")
    update_supported_contracts("FacetBuddyFactory")
    update_supported_contracts("FacetBuddy")
    update_supported_contracts("NFTCollection01")
  end
  
  it "does things" do
    erc20Bridge = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "EtherBridge03",
          args: {
            name: "Facet Ether",
            symbol: "FETH",
            trustedSmartContract: trusted_smart_contract
          }
        }
      }
    )
    
    factory = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "FacetBuddyFactory",
          args: {
            erc20Bridge: erc20Bridge.address,
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :call,
        data: {
          to: erc20Bridge.address,
          function: "setFacetBuddyFactory",
          args: factory.address
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: :call,
        data: {
          to: erc20Bridge.address,
          function: "bridgeIn",
          args: {
            to: bob,
            amount: 1000
          }
        }
      }
    )
    
    bridge = erc20Bridge
    
    nft_contract = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "NFTCollection01",
          args: {
            name: name,
            symbol: symbol,
            maxSupply: max_supply,
            baseURI: base_uri,
            weth: bridge.address,
            perMintFee: per_mint_fee,
            feeTo: fee_to_address
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        to: nft_contract.address,
        data: {
          function: "setPublicMintSettings",
          args: {
            publicMaxPerAddress: 0,
            publicMintStart: 1,
            publicMintEnd: 0,
            publicMintPrice: 1.ether
          }
        }
      }
    )
    
    call_data = {
      function: "airdrop",
      args: {
        to: daryl,
        amount: 3,
        merkleProof: []
      }
    }.to_json
    
    mint_fee = 3 * per_mint_fee
    
    nft_balance = ContractTransaction.make_static_call(
      contract: nft_contract.address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    expect(nft_balance).to eq(0)
    
    expected_buddy_address = ContractTransaction.make_static_call(
      contract: bridge.address,
      function_name: "predictBuddyAddress",
      function_args: daryl
    )
    
    trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: :call,
        data: {
          to: bridge.address,
          function: "bridgeAndCall",
          args: {
            to: daryl,
            amount: 5.ether,
            addressToCall: nft_contract.address,
            base64Calldata: Base64.strict_encode64(call_data)
          }
        }
      }
    )
    
    actual_buddy_address = ContractTransaction.make_static_call(
      contract: factory.address,
      function_name: "buddyForUser",
      function_args: daryl
    )
    
    expect(actual_buddy_address).to eq(expected_buddy_address)
    
    nft_balance = ContractTransaction.make_static_call(
      contract: nft_contract.address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    expect(nft_balance).to eq(3)
    
    eth_balance = ContractTransaction.make_static_call(
      contract: bridge.address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    expect(eth_balance).to eq(2.ether - mint_fee)
    
    call_data = ["airdrop", charlie, 3, []].to_json
    
    trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: :call,
        data: {
          to: bridge.address,
          function: "bridgeAndCall",
          args: [
            charlie,
            5.ether,
            nft_contract.address,
            Base64.strict_encode64(call_data)
          ]
        }
      }
    )
    
    nft_balance = ContractTransaction.make_static_call(
      contract: nft_contract.address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    expect(nft_balance).to eq(3)
    
    eth_balance = ContractTransaction.make_static_call(
      contract: bridge.address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    expect(eth_balance).to eq(2.ether - mint_fee)
  end
end