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
  let(:fee) { (0.0005.to_d * 1.ether).to_i }
  let(:fee_to_address) { "0xf00000000000000000000000000000000000000f" }
  let(:per_mint_fee) { (0.0005.to_d * 1.ether).to_i }
  
  before(:all) do
    update_supported_contracts("EtherBridge02")
    update_supported_contracts("BridgeAndCallHelper")
    update_supported_contracts("NFTCollection01")
  end
  
  it "does things" do
    helper = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "BridgeAndCallHelper",
          args: {
            bridge: "0x0000000000000000000000000000000000000000",
            owner: alice,
            fee: fee
          }
        }
      }
    )
    
    bridge = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "EtherBridge02",
          args: {
            name: "Facet Ether",
            symbol: "FETH",
            trustedSmartContract: trusted_smart_contract,
            bridgeAndCallHelper: helper.address
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :call,
        data: {
          to: helper.address,
          function: "setBridge",
          args: bridge.address
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: trusted_smart_contract,
      payload: {
        op: :call,
        data: {
          to: bridge.address,
          function: "bridgeIn",
          args: {
            to: bob,
            amount: 1000
          }
        }
      }
    )
    
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
    
    expect(eth_balance).to eq(2.ether - fee - mint_fee)
    
    eth_balance = ContractTransaction.make_static_call(
      contract: bridge.address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    expect(eth_balance).to eq(fee)
    
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
    
    expect(eth_balance).to eq(2.ether - fee - mint_fee)
  end
end