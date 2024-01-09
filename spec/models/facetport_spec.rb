require 'rails_helper'

describe 'FacetPort contract' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice_key) { Eth::Key.new(priv: "0" * 63 + "1") }
  let(:alice) { alice_key.address.address }
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
    
    royaltyBps = 420
    nft = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "StubERC721",
          args: {
            name: "Tester",
            royaltyReceiver: charlie,
            royaltyBps: royaltyBps
          }
        }
      }
    )
    
    aliceNFTs = (0..9).to_a
    bobNFTs = (55..64).to_a
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: nft.address,
          function: "mint",
          args: {
            to: alice,
            ids: aliceNFTs
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        op: "call",
        data: {
          to: nft.address,
          function: "mint",
          args: {
            to: bob,
            ids: bobNFTs
          }
        }
      }
    )
    
    feeBps = 500
    
    market = trigger_contract_interaction_and_expect_success(
      from: daryl,
      payload: {
        op: :create,
        data: {
          type: "FacetPortV1",
          args: {
            _feeBps: feeBps,
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
      
      trigger_contract_interaction_and_expect_success(
        from: minter,
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
    end
    
    listing_id = "0x" + SecureRandom.hex(32)
    start_time = Time.current.to_i
    end_time = 1000.years.from_now.to_i
    
    typed_data = {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ],
        Listing: [
          { name: "listingId", type: "bytes32" },
          { name: "seller", type: "address" },
          { name: "assetContract", type: "address" },
          { name: "assetId", type: "uint256" },
          { name: "currency", type: "address" },
          { name: "price", type: "uint256" },
          { name: "startTime", type: "uint256" },
          { name: "endTime", type: "uint256" }
        ]
      },
      primaryType: "Listing",
      domain: {
        name: "FacetPort",
        version: '1',
        chainId: chainid,
        verifyingContract: market.address
      },
      message: {
        listingId: listing_id,
        seller: alice,
        assetContract: nft.address,
        assetId: aliceNFTs.first,
        currency: weth.address,
        price: 1.ether,
        startTime: start_time,
        endTime: end_time
      }
    }
    
    signature = alice_key.sign_typed_data(typed_data, chainid)
    
    alice_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    bob_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: bob
    )
    
    daryl_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    charlie_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    price = 1.ether
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "buyWithSignature",
          args: {
            listingId: listing_id,
            seller: alice,
            assetContract: nft.address,
            assetId: aliceNFTs.first,
            currency: weth.address,
            price: price,
            startTime: start_time,
            endTime: end_time,
            signature: "0x" + signature
          }
        }
      }
    )
    
    alice_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: alice
    )
    
    bob_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: bob
    )
    
    daryl_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: daryl
    )
    
    charlie_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: charlie
    )
    
    expected_alice_balance = alice_initial_balance + price - (price * feeBps / 10_000) - (price * royaltyBps / 10_000)
    expected_bob_balance = bob_initial_balance - price
    expected_daryl_balance = daryl_initial_balance + (price * feeBps / 10_000)
    expected_charlie_balance = charlie_initial_balance + (price * royaltyBps / 10_000)

    # Check the final balances
    expect(alice_final_balance).to eq(expected_alice_balance)
    expect(bob_final_balance).to eq(expected_bob_balance)
    expect(daryl_final_balance).to eq(expected_daryl_balance)
    expect(charlie_final_balance).to eq(expected_charlie_balance)

    # Check that Bob now owns the NFT
    nft_owner = ContractTransaction.make_static_call(
      contract: nft.address,
      function_name: "ownerOf",
      function_args: aliceNFTs.first
    )
    expect(nft_owner).to eq(bob)
    
    bid_id = "0x" + SecureRandom.hex(32)
    start_time = Time.current.to_i
    end_time = 1000.years.from_now.to_i
    bid_amount = 2.ether
    
    typed_data = {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ],
        Bid: [
          { name: "bidId", type: "bytes32" },
          { name: "bidder", type: "address" },
          { name: "assetContract", type: "address" },
          { name: "assetId", type: "uint256" },
          { name: "currency", type: "address" },
          { name: "bidAmount", type: "uint256" },
          { name: "startTime", type: "uint256" },
          { name: "endTime", type: "uint256" }
        ]
      },
      primaryType: "Bid",
      domain: {
        name: "FacetPort",
        version: '1',
        chainId: chainid,
        verifyingContract: market.address
      },
      message: {
        bidId: bid_id,
        bidder: alice,
        assetContract: nft.address,
        assetId: 0,
        currency: weth.address,
        bidAmount: bid_amount,
        startTime: start_time,
        endTime: end_time
      }
    }
  
    signature = alice_key.sign_typed_data(typed_data, chainid)
  
    alice_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: alice
    )
  
    bob_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: bob
    )
    
    trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "acceptBidWithSignature",
          args: {
            bidId: bid_id,
            bidder: alice,
            assetContract: nft.address,
            assetId: 0,
            currency: weth.address,
            bidAmount: bid_amount,
            startTime: start_time,
            endTime: end_time,
            signature: "0x" + signature
          }
        }
      }
    )
    
    alice_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: alice
    )
  
    bob_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: bob
    )
  
    expected_bob_balance = bob_initial_balance + bid_amount - (bid_amount * feeBps / 10_000) - (bid_amount * royaltyBps / 10_000)
    expected_alice_balance = alice_initial_balance - bid_amount
  
    expect(alice_final_balance).to eq(expected_alice_balance)
    expect(bob_final_balance).to eq(expected_bob_balance)
  
    nft_owner = ContractTransaction.make_static_call(
      contract: nft.address,
      function_name: "ownerOf",
      function_args: 0
    )
    expect(nft_owner).to eq(alice)
    
    bid_count = 5
    bid_ids = bid_count.times.map { "0x" + SecureRandom.hex(32) }
    start_time = Time.current.to_i
    end_time = 1000.years.from_now.to_i
    bid_amounts = Array.new(bid_count, 2.ether)
    token_ids = bobNFTs.last(bid_count)
    
    typed_data_array = bid_ids.map.with_index do |bid_id, idx|
      {
        types: {
          EIP712Domain: [
            { name: "name", type: "string" },
            { name: "version", type: "string" },
            { name: "chainId", type: "uint256" },
            { name: "verifyingContract", type: "address" }
          ],
          Bid: [
            { name: "bidId", type: "bytes32" },
            { name: "bidder", type: "address" },
            { name: "assetContract", type: "address" },
            { name: "assetId", type: "uint256" },
            { name: "currency", type: "address" },
            { name: "bidAmount", type: "uint256" },
            { name: "startTime", type: "uint256" },
            { name: "endTime", type: "uint256" }
          ]
        },
        primaryType: "Bid",
        domain: {
          name: "FacetPort",
          version: '1',
          chainId: chainid,
          verifyingContract: market.address
        },
        message: {
          bidId: bid_id,
          bidder: alice,
          assetContract: nft.address,
          assetId: token_ids[idx],
          currency: weth.address,
          bidAmount: bid_amounts[idx],
          startTime: start_time,
          endTime: end_time
        }
      }
    end
    
    signatures = typed_data_array.map { |typed_data| alice_key.sign_typed_data(typed_data, chainid) }
  
    alice_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: alice
    )
  
    bob_initial_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: bob
    )
    
    res = trigger_contract_interaction_and_expect_success(
      from: bob,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "acceptMultipleBidsWithSignatures",
          args: {
            bidIds: bid_ids,
            bidders: Array.new(bid_count, alice),
            assetContracts: Array.new(bid_count, nft.address),
            assetIds: token_ids,
            currencies: Array.new(bid_count, weth.address),
            bidAmounts: bid_amounts,
            startTimes: Array.new(bid_count, start_time),
            endTimes: Array.new(bid_count, end_time),
            signatures: signatures.map { |sig| "0x" + sig }
          }
        }
      }
    )
    
    alice_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: alice
    )
  
    bob_final_balance = ContractTransaction.make_static_call(
      contract: weth.address,
      function_name: "balanceOf",
      function_args: bob
    )
  
    expected_bob_balance = bob_initial_balance + bid_amounts.sum - (bid_amounts.sum * feeBps / 10_000) - (bid_amounts.sum * royaltyBps / 10_000)
    expected_alice_balance = alice_initial_balance - bid_amounts.sum
  
    expect(alice_final_balance).to eq(expected_alice_balance)
    expect(bob_final_balance).to eq(expected_bob_balance)
  
    token_ids.each do |asset_id|
      nft_owner = ContractTransaction.make_static_call(
        contract: nft.address,
        function_name: "ownerOf",
        function_args: asset_id
      )
      expect(nft_owner).to eq(alice)
    end
  end
  
  it "Cancels a listing" do
    market = trigger_contract_interaction_and_expect_success(
      from: daryl,
      payload: {
        op: :create,
        data: {
          type: "FacetPortV1",
          args: {
            _feeBps: 1,
            startPaused: false
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "cancelListing",
          args: {
            listingId: "0x" + SecureRandom.hex(32)
          }
        }
      }
    )
  
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "cancelAllListingsForAsset",
          args: {
            assetContract: "0x0000000000000000000000000000000000000001",
            assetId: 0
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: "call",
        data: {
          to: market.address,
          function: "cancelAllListingsOfUser"
        }
      }
    )
  end
end