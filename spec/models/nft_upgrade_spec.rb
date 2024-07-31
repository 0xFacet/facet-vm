require 'rails_helper'

RSpec.describe "TokenUpgradeRenderer01", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:daryl) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:charlie) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let(:trusted_smart_contract) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let(:owner_address) { "0x000000000000000000000000000000000000000a" }
  let(:non_owner_address) { "0x000000000000000000000000000000000000000b" }
  let(:allow_list_address) { "0x000000000000000000000000000000000000000c" }
  let(:fee_to_address) { "0xf00000000000000000000000000000000000000f" }
  let(:per_mint_fee) { (0.0005.to_d * 1.ether).to_i }
  let(:weth_contract) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "PublicMintERC20",
          args: {
            name: "WETH",
            symbol: "WETH",
            maxSupply: 100_000_000_000.ether,
            perMintLimit: 1_000_000.ether,
            decimals: 18
          }
        }
      }
    )
  end
  let(:max_supply) { 10000 }
  let(:base_uri) { "https://example.com/" }
  let(:name) { "TestNFT" }
  let(:symbol) { "TNFT" }
  let(:nft_contract) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "NFTCollection01",
          args: {
            name: name,
            symbol: symbol,
            maxSupply: max_supply,
            baseURI: base_uri,
            weth: weth_contract.address,
            perMintFee: per_mint_fee,
            feeTo: fee_to_address
          }
        }
      }
    )
  end
  let(:merkle_proof) { [
    "0xd73fe8dee98c00bc502eb5e68b20c51dbf3cd4f79151d5a836baed2d694e569f",
    "0xa582328d0d0105f80325c9b25d15ba38e45b10cb83df026376d2c8c46e0fe3ea"
  ] }
  let(:merkle_root) { "0x15dc0cbc02451d6f93b9433b989dd9eb5da9456cdf9bfb91bdd1f7008c28f0e6" }
  let(:owner_weth_balance) { "0" }
  let(:non_owner_weth_balance) { "0" }
  let(:allow_list_weth_balance) { "0" }
  
  before(:all) do
    update_supported_contracts(
      "TokenUpgradeRenderer01",
      "NFTCollection01",
      "EtherBridge03",
      "FacetBuddyFactory",
      "FacetBuddy",
      "TokenUpgradeRenderer02",
      "PublicMintERC20"
    )
  end

  def set_public_mint_settings(
      public_max_per_address:,
      public_mint_start:,
      public_mint_end:,
      public_mint_price:
  )
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: nft_contract.address,
        data: {
          function: "setPublicMintSettings",
          args: {
            publicMaxPerAddress: public_max_per_address,
            publicMintStart: public_mint_start,
            publicMintEnd: public_mint_end,
            publicMintPrice: public_mint_price
          }
        }
      }
    )
  end

  def set_allow_list_mint_settings(
    allow_list_merkle_root:,
    allow_list_max_per_address:,
    allow_list_mint_start:,
    allow_list_mint_end:,
    allow_list_mint_price:
  )
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: nft_contract.address,
        data: {
          function: "setAllowListMintSettings",
          args: {
            allowListMerkleRoot: allow_list_merkle_root,
            allowListMaxPerAddress: allow_list_max_per_address,
            allowListMintStart: allow_list_mint_start,
            allowListMintEnd: allow_list_mint_end,
            allowListMintPrice: allow_list_mint_price
          }
        }
      }
    )
  end

  def set_weth_allowance(wallet:, spender: nft_contract.address, amount:)
    trigger_contract_interaction_and_expect_success(
      from: wallet,
      payload: {
        to: weth_contract.address,
        data: {
          function: "approve",
          args: {
            spender: spender,
            amount: amount
          }
        }
      }
    )
  end

  def get_contract_state(contract_address, function_name, *args, **kwargs)
    result = ContractTransaction.make_static_call(
      contract: contract_address,
      function_name: function_name,
      function_args: kwargs.presence || args
    )
    result
  end

  def get_contract_state(contract_address, function_name, *args, **kwargs)
    result = ContractTransaction.make_static_call(
      contract: contract_address,
      function_name: function_name,
      function_args: kwargs.presence || args
    )
    result
  end

  before do
    trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: weth_contract.address,
        data: {
          function: "mint",
          args: {
            amount: 1_000_000.ether
          }
        }
      }
    )
    trigger_contract_interaction_and_expect_success(
      from: allow_list_address,
      payload: {
        to: weth_contract.address,
        data: {
          function: "mint",
          args: {
            amount: 1_000_000.ether
          }
        }
      }
    )

    owner_weth_balance = get_contract_state(weth_contract.address, "balanceOf", owner_address)
    non_owner_weth_balance = get_contract_state(weth_contract.address, "balanceOf", non_owner_address)
    allow_list_weth_balance = get_contract_state(weth_contract.address, "balanceOf", allow_list_address)
  end
  
  it 'deploys the upgrader' do
    factory = trigger_contract_interaction_and_expect_success(
      from: alice,
      payload: {
        op: :create,
        data: {
          type: "FacetBuddyFactory",
          args: {
            erc20Bridge: weth_contract.address,
          }
        }
      }
    )
    
    upgrader = trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "TokenUpgradeRenderer01",
          args: {
            perUpgradeFee: per_mint_fee,
            feeTo: fee_to_address,
            weth: weth_contract.address
          }
        }
      }
    )
    
    r = trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: nft_contract.address,
        data: {
          function: "setMetadataRenderer",
          args: {
            metadataRenderer: upgrader.address,
            data: {
              function: "initializeWithData",
              args: {
                initialLevel: {
                  name: "Level 1",
                  imageURI: "https://example.com/image.png",
                  animationURI: "https://example.com/animation.png",
                  extraAttributesJson: "",
                  startTime: 0,
                  endTime: 0,
                },
                contractInfo: {
                  name: "Test Name",
                  description: "Test contract description",
                  imageURI: "https://test.com/image.png"
                }
              }
            }.to_json
          }
        }
      }
    )
    
    new_level = {
      name: "Level 2",
      imageURI: "https://example.com/image2.png",
      animationURI: "",
      extraAttributesJson: {
        "trait_type": "Defining Trait", "value": "Mohawk"
      }.to_json,
      startTime: Time.now.to_i + 30.minutes,
      endTime: Time.now.to_i + 1.day,
    }
    
    expect {
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          to: upgrader.address,
          data: {
            function: "addUpgradeLevel",
            args: {
              collection: nft_contract.address,
              newLevel: new_level
            }
          }
        }
      )
    }.to change { get_contract_state(upgrader.address, "upgradeLevelCount", nft_contract.address) }.by(1)
    
    edited_level_2 = new_level.merge(name: "Edited Level 2")
    
    current_2 = get_contract_state(upgrader.address, "tokenUpgradeLevelsByCollection", nft_contract.address, 1)
    
    expect(current_2['name']).to eq("Level 2")
    
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: upgrader.address,
        data: {
          function: "editUpgradeLevel",
          args: {
            collection: nft_contract.address,
            index: 1,
            newLevel: edited_level_2
          }
        }
      }
    )
    
    new_2 = get_contract_state(upgrader.address, "tokenUpgradeLevelsByCollection", nft_contract.address, 1)
    
    expect(new_2['name']).to eq("Edited Level 2")
    
    set_public_mint_settings(
      public_max_per_address: 0,
      public_mint_start: 1,
      public_mint_end: 0,
      public_mint_price: 0
    )
    
    amount = 5
    set_weth_allowance(wallet: non_owner_address, amount: amount * per_mint_fee)

    trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: nft_contract.address,
        data: {
          function: "mint",
          args: {
            amount: amount,
            merkleProof: []
          }
        }
      }
    )
    
    active_level = get_contract_state(upgrader.address, "activeUpgradeLevelIndex", nft_contract.address)
    
    expect(active_level).to eq(0)
    
    travel_to Time.current + 1.hour

    active_level = get_contract_state(upgrader.address, "activeUpgradeLevelIndex", nft_contract.address)
    
    expect(active_level).to eq(1)
    
    set_weth_allowance(
      wallet: non_owner_address,
      spender: upgrader.address,
      amount: amount * per_mint_fee
    )
    
    token_uri_base_64 = get_contract_state(nft_contract.address, "tokenURI", 1)
    
    token_uri = JSON.parse(Base64.decode64(token_uri_base_64.split("data:application/json;base64,").last))
    
    expect(token_uri["attributes"].none? { |attr| attr["trait_type"] == "Last Upgrade Level" }).to be true
    
    trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: upgrader.address,
        data: {
          function: "upgradeMultipleTokens",
          args: {
            collection: nft_contract.address,
            tokenIds: [1, 2]
          }
        }
      }
    )
    
    token_uri_base_64 = get_contract_state(nft_contract.address, "tokenURI", 1)
    
    token_uri = JSON.parse(Base64.decode64(token_uri_base_64.split("data:application/json;base64,").last))
    
    expect(token_uri["attributes"].any? { |attr| attr["trait_type"] == "Last Upgrade Level" }).to be true
    expect(token_uri['image']).to eq("https://example.com/image2.png")
    
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: "Token already upgraded during this period",
      from: non_owner_address,
      payload: {
        to: upgrader.address,
        data: {
          function: "upgradeMultipleTokens",
          args: {
            collection: nft_contract.address,
            tokenIds: [1, 2]
          }
        }
      }
    )
    
    buddy_receipt = trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: factory.address,
        data: {
          function: "findOrCreateBuddy",
          args: non_owner_address
        }
      }
    )
    
    buddy_address = buddy_receipt.logs.detect { |log| log['event'] == "BuddyCreated" }['data']['buddy']
    
    trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: nft_contract.address,
        data: {
          function: "setApprovalForAll",
          args: {
            operator: buddy_address,
            approved: true
          }
        }
      }
    )
    
    set_weth_allowance(
      wallet: non_owner_address,
      spender: buddy_address,
      amount: 2  ** 256 - 1
    )
    
    calldata = {
      function: "upgradeMultipleTokens",
      args: {
        collection: nft_contract.address,
        tokenIds: [3, 4]
      }
    }
    
    trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: factory.address,
        data: {
          function: "callBuddyForUser",
          args: {
            amountToSpend: per_mint_fee * 2,
            addressToCall: upgrader.address,
            calldata: calldata.to_json
          }
        }
      }
    )
    
    token_uri_base_64 = get_contract_state(nft_contract.address, "tokenURI", 4)
    
    token_uri = JSON.parse(Base64.decode64(token_uri_base_64.split("data:application/json;base64,").last))
    
    expect(token_uri['image']).to eq("https://example.com/image2.png")
    
    calldata = {
      function: "upgradeMultipleTokens",
      args: {
        collection: nft_contract.address,
        tokenIds: [5]
      }
    }
    
    trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: buddy_address,
        data: {
          function: "callForUser",
          args: {
            amountToSpend: per_mint_fee * 2,
            addressToCall: upgrader.address,
            calldata: calldata.to_json
          }
        }
      }
    )
    
    expect(get_contract_state(weth_contract.address, "balanceOf", buddy_address)).to eq(0)
    
    contract_uri_base_64 = get_contract_state(nft_contract.address, "contractURI")
    
    contract_uri = JSON.parse(Base64.decode64(contract_uri_base_64.split("data:application/json;base64,").last))
    
    expect(contract_uri['description']).to eq("Test contract description")
    
    v2 = RubidityTranspiler.transpile_and_get("TokenUpgradeRenderer02")

    upgrade_tx = trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: upgrader.address,
        data: {
          function: "upgrade",
          args: [v2.legacy_init_code_hash, v2.source_code]
        }
      }
    )
    
    new_level = {
      name: "Level 3",
      imageURI: "https://example.com/image2.png",
      animationURI: "",
      extraAttributesJson: {
        "trait_type": "Defining Trait", "value": "Mohawk"
      }.to_json,
      startTime: Time.now.to_i + 30.days,
      endTime: Time.now.to_i + 31.days,
    }
    
    expected_images = [
      "https://example.com/image_array4.png",
      "https://example.com/image_array3.png",
      "https://example.com/image_array.png",
      "https://example.com/image_array2.png"
    ]
    
    expect {
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          to: upgrader.address,
          data: {
            function: "addUpgradeLevel",
            args: {
              collection: nft_contract.address,
              newLevel: new_level,
              imageURIs: expected_images
            }
          }
        }
      )
    }.to change { get_contract_state(upgrader.address, "upgradeLevelCount", nft_contract.address) }.by(1)
    
    travel_to Time.current + 30.days + 1.hour
    
    active_level = get_contract_state(upgrader.address, "activeUpgradeLevelIndex", nft_contract.address)
    
    expect(active_level).to eq(2)
    
    set_weth_allowance(
      wallet: non_owner_address,
      spender: upgrader.address,
      amount: amount * per_mint_fee
    )
    
    r = trigger_contract_interaction_and_expect_success(
      from: non_owner_address,
      payload: {
        to: upgrader.address,
        data: {
          function: "upgradeMultipleTokens",
          args: {
            collection: nft_contract.address,
            tokenIds: [1, 2]
          }
        }
      }
    )
    # puts JSON.pretty_generate(r.stats.nested_log)
    # exit
    
    token_uri_base_64 = get_contract_state(nft_contract.address, "tokenURI", 1)
    
    token_uri = JSON.parse(Base64.decode64(token_uri_base_64.split("data:application/json;base64,").last))
    
    expect(token_uri["attributes"].any? { |attr| attr["trait_type"] == "Last Upgrade Level" }).to be true
    expect(expected_images).to include(token_uri['image'])
    
    trigger_contract_interaction_and_expect_error(
      from: owner_address,
      payload: {
        to: upgrader.address,
        data: {
          function: "addUpgradeLevel",
          args: {
            collection: nft_contract.address,
            newLevel: new_level,
            imageURIs: expected_images * 10
          }
        }
      }
    )
  end
end
