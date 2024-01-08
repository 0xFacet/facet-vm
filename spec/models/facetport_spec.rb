require 'rails_helper'

describe 'FacetPort contract' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0x000000000000000000000000000000000000000a" }
  let(:bob) { "0x000000000000000000000000000000000000000b" }
  let(:charlie) { "0x000000000000000000000000000000000000000c" }
  let(:daryl) { "0x000000000000000000000000000000000000000d" }
  
  before(:all) do
    update_supported_contracts("FacetPortV1")
    update_supported_contracts("StubERC721")
    update_supported_contracts("StubERC20")
  end
  
  it "Lists and sells" do
    weth = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "StubERC20",
          args: {
            name: "WETH",
          }
        }
      }
    )
    
    nft = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "StubERC721",
          args: {
            name: "Tester",
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: nft.address,
          function: "mint",
          args: 10
        }
      }
    )
    
    market = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "FacetPortV1",
          args: {
            _feeBps: 500,
            startPaused: false
          }
        }
      }
    )
    
    [alice, bob].each do |minter|
      trigger_contract_interaction_and_expect_success(
        from: minter,
        payload: {
          op: "call",
          data: {
            to: weth.address,
            function: "mint",
            args: 100.ether
          }
        }
      )
      trigger_contract_interaction_and_expect_success(
        from: minter,
        payload: {
          op: "call",
          data: {
            to: weth.address,
            function: "approve",
            args: {
              spender: market.address,
              amount: 100000.ether
            }
          }
        }
      )
    end
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: nft.address,
          function: "setApprovalForAll",
          args: {
            operator: market.address,
            approved: true
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "buyWithSignature",
          args: {
            seller: alice,
            assetContract: nft.address,
            assetId: 0,
            currency: weth.address,
            price: 1.ether
          }
        }
      }
    )
  end
end