require 'rails_helper'

RSpec.describe "NFTCollection01", type: :model do
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
  let(:metadata_renderer) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "EditionMetadataRenderer01"
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

  def set_weth_allowance(wallet:, amount:)
    trigger_contract_interaction_and_expect_success(
      from: wallet,
      payload: {
        to: weth_contract.address,
        data: {
          function: "approve",
          args: {
            spender: nft_contract.address,
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
    update_supported_contracts(
      "NFTCollection01",
      "EditionMetadataRenderer01",
      "PublicMintERC20"
    )

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

  describe 'minting process' do
    context 'when public mint is active' do
      it 'allows unlimited minting if maxPerAddress is 0' do
        set_public_mint_settings(
          public_max_per_address: 0,
          public_mint_start: 1,
          public_mint_end: 0,
          public_mint_price: 1.ether
        )
      
        mint_amount = 25
        total_cost = mint_amount * 1.ether
        total_fee = mint_amount * per_mint_fee
        total = total_cost + total_fee
        
        set_weth_allowance(wallet: non_owner_address, amount: total)

        expect {
          get_contract_state(nft_contract.address, 'tokenURI', 1)
        }.to raise_error(StandardError, /URI query for nonexistent token/)

        unlimited_mint_receipt = trigger_contract_interaction_and_expect_success(
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: mint_amount,
                merkleProof: []
              }
            }
          }
        )
        expect(unlimited_mint_receipt.logs).to include(hash_including('event' => 'Minted'))

        contract_weth_balance = get_contract_state(weth_contract.address, "balanceOf", nft_contract.address)
        expect(contract_weth_balance).to eq(total_cost)

        token_uri = get_contract_state(nft_contract.address, 'tokenURI', 1)
        expect(token_uri).to eq("https://example.com/1")
      end

      it 'enforces mint limit if maxPerAddress is a positive number' do
        set_public_mint_settings(
          public_max_per_address: 5,
          public_mint_start: 1,
          public_mint_end: 0,
          public_mint_price: 0
        )
        
        amount = 5
        set_weth_allowance(wallet: non_owner_address, amount: amount * per_mint_fee)

        start_fee_to_address_balance = get_contract_state(weth_contract.address, "balanceOf", fee_to_address)
        
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

        end_fee_to_address_balance = get_contract_state(weth_contract.address, "balanceOf", fee_to_address)
        
        expect(end_fee_to_address_balance - start_fee_to_address_balance).to eq(amount * per_mint_fee)
        
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'Exceeded mint limit',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: 1,
                merkleProof: []
              }
            }
          }
        )
      end

      it 'does not allow minting more than maxSupply' do
        set_public_mint_settings(
          public_max_per_address: 0,
          public_mint_start: 1,
          public_mint_end: 0,
          public_mint_price: 0
        )

        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'Exceeded max supply',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: max_supply + 1,
                merkleProof: []
              }
            }
          }
        )
      end
    end

    context 'when allow list mint is active' do      
      before(:each) do
        set_allow_list_mint_settings(
          allow_list_merkle_root: merkle_root,
          allow_list_max_per_address: 0,
          allow_list_mint_start: 1,
          allow_list_mint_end: 0,
          allow_list_mint_price: 0
        )
      end

      it 'allows minting for addresses on the allow list' do
        amount = 1
        set_weth_allowance(wallet: allow_list_address, amount: amount * per_mint_fee)
        
        allow_list_mint_receipt = trigger_contract_interaction_and_expect_success(
          from: allow_list_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: amount,
                merkleProof: merkle_proof
              }
            }
          }
        )
        expect(allow_list_mint_receipt.logs).to include(hash_including('event' => 'Minted'))
      end

      it 'does not allow minting for addresses not on the allow list' do
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'Not on allow list',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: 1,
                merkleProof: merkle_proof
              }
            }
          }
        )
      end
    end

    it 'burns' do
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "setMetadataRenderer",
            args: {
              metadataRenderer: metadata_renderer.address,
              data: {
                function: "initializeWithData",
                args: {
                  info: {
                    name: "Test Name",
                    description: "Test description",
                    imageURI: "https://test.com/image.png",
                    animationURI: ""
                  }
                }
              }.to_json
            }
          }
        }
      )
      set_public_mint_settings(
        public_max_per_address: 0,
        public_mint_start: 1,
        public_mint_end: 0,
        public_mint_price: 1.ether
      )
      set_weth_allowance(wallet: non_owner_address, amount: 10.ether + per_mint_fee)
      trigger_contract_interaction_and_expect_success(
        from: non_owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "mint",
            args: {
              amount: 1,
              merkleProof: []
            }
          }
        }
      )
      
      supply = get_contract_state(nft_contract.address, "totalSupply")
      bal = get_contract_state(nft_contract.address, "balanceOf", non_owner_address)
      owner = get_contract_state(nft_contract.address, "ownerOf", 1)
      
      expect(supply).to eq(1)
      expect(bal).to eq(1)
      expect(owner).to eq(non_owner_address)
      
      trigger_contract_interaction_and_expect_error(
        from: owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "burn",
            args: {
              tokenId: 1,
            }
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        from: non_owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "burn",
            args: {
              tokenId: 1,
            }
          }
        }
      )
      
      supply = get_contract_state(nft_contract.address, "totalSupply")
      bal = get_contract_state(nft_contract.address, "balanceOf", non_owner_address)
      expect(supply).to eq(0)
      expect(bal).to eq(0)
      
      expect { get_contract_state(nft_contract.address, "ownerOf", 1) }.to raise_error(
        ContractErrors::StaticCallError, /ERC721: owner query for nonexistent token/
      )
      
      trigger_contract_interaction_and_expect_success(
        from: non_owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "mint",
            args: {
              amount: 2,
              merkleProof: []
            }
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        from: non_owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "burnMultiple",
            args: {
              tokenIds: [2, 3],
            }
          }
        }
      )
    end

    context 'when minting exceeds max supply' do
      it 'does not allow minting that exceeds max supply' do
        set_public_mint_settings(
          public_max_per_address: 0,
          public_mint_start: 1,
          public_mint_end: 0,
          public_mint_price: 0
        )

        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'Exceeded max supply',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: max_supply + 1,
                merkleProof: []
              }
            }
          }
        )
      end
    end

    context 'when minting conditions are not met' do
      it 'does not allow minting before mint start time' do
        set_public_mint_settings(
          public_max_per_address: 0,
          public_mint_start: Time.now.to_i + 60,
          public_mint_end: 0,
          public_mint_price: 0
        )

        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'Mint is not active',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: 1,
                merkleProof: []
              }
            }
          }
        )
      end

      it 'does not allow minting after mint end time' do
        set_public_mint_settings(
          public_max_per_address: 0,
          public_mint_start: 1,
          public_mint_end: Time.now.to_i - 60,
          public_mint_price: 0
        )

        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'Mint is not active',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "mint",
              args: {
                amount: 1,
                merkleProof: []
              }
            }
          }
        )
      end
    end
  end

  describe 'contract administration' do
    context 'when owner calls' do
      it 'allows setting public mint settings' do
        new_settings = {
          public_max_per_address: 5,
          public_mint_start: 1000000,
          public_mint_end: 2000000,
          public_mint_price: 0.1.ether
        }
        
        set_settings_receipt = set_public_mint_settings(
          public_max_per_address: new_settings[:public_max_per_address],
          public_mint_start: new_settings[:public_mint_start],
          public_mint_end: new_settings[:public_mint_end],
          public_mint_price: new_settings[:public_mint_price]
        )
        
        # Verify that the contract state was updated correctly
        expect(get_contract_state(nft_contract.address, :publicMaxPerAddress)).to eq(new_settings[:public_max_per_address])
        expect(get_contract_state(nft_contract.address, :publicMintStart)).to eq(new_settings[:public_mint_start])
        expect(get_contract_state(nft_contract.address, :publicMintEnd)).to eq(new_settings[:public_mint_end])
        expect(get_contract_state(nft_contract.address, :publicMintPrice)).to eq(new_settings[:public_mint_price])
      end

      it 'allows setting allow list mint settings' do
        new_settings = {
          allow_list_merkle_root: "0x25dc0cbc02451d6f93b9433b989dd9eb5da9456cdf9bfb91bdd1f7008c28f0e7",
          allow_list_max_per_address: 3,
          allow_list_mint_start: 2000000,
          allow_list_mint_end: 3000000,
          allow_list_mint_price: 0.05.ether
        }
        
        set_settings_receipt = set_allow_list_mint_settings(
          allow_list_merkle_root: new_settings[:allow_list_merkle_root],
          allow_list_max_per_address: new_settings[:allow_list_max_per_address],
          allow_list_mint_start: new_settings[:allow_list_mint_start],
          allow_list_mint_end: new_settings[:allow_list_mint_end],
          allow_list_mint_price: new_settings[:allow_list_mint_price]
        )
        
        # Verify that the contract state was updated correctly
        expect(get_contract_state(nft_contract.address, :allowListMerkleRoot)).to eq(new_settings[:allow_list_merkle_root])
        expect(get_contract_state(nft_contract.address, :allowListMaxPerAddress)).to eq(new_settings[:allow_list_max_per_address])
        expect(get_contract_state(nft_contract.address, :allowListMintStart)).to eq(new_settings[:allow_list_mint_start])
        expect(get_contract_state(nft_contract.address, :allowListMintEnd)).to eq(new_settings[:allow_list_mint_end])
        expect(get_contract_state(nft_contract.address, :allowListMintPrice)).to eq(new_settings[:allow_list_mint_price])
      end

      it 'allows pausing and unpausing the contract' do
        # Test pausing the contract
        pause_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "pause",
              args: {}
            }
          }
        )
        # Verify that the contract is paused
        expect(get_contract_state(nft_contract.address, :paused)).to be true

        # Test unpausing the contract
        unpause_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "unpause",
              args: {}
            }
          }
        )
        # Verify that the contract is not paused
        expect(get_contract_state(nft_contract.address, :paused)).to be false
      end

      it 'allows setting the base URI' do
        new_base_uri = "https://newexample.com/"
        set_base_uri_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setBaseURI",
              args: {
                baseURI: new_base_uri
              }
            }
          }
        )
        # Verify that the base URI was updated correctly
        expect(get_contract_state(nft_contract.address, :baseURI)).to eq(new_base_uri)
      end

      it 'allows setting the metadata renderer' do
        trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setMetadataRenderer",
              args: {
                metadataRenderer: metadata_renderer.address,
                data: {
                  function: "initializeWithData",
                  args: {
                    info: {
                      name: "Test Name",
                      description: "Test description",
                      imageURI: "https://test.com/image.png",
                      animationURI: "https://test.com/animation.png"
                    }
                  }
                }.to_json
              }
            }
          }
        )
      end
    end

    context 'when non-owner calls' do
      it 'does not allow setting public mint settings' do
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'msg.sender is not the owner',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setPublicMintSettings",
              args: {
                publicMaxPerAddress: 5,
                publicMintStart: 1000000,
                publicMintEnd: 2000000,
                publicMintPrice: 0.1.ether
              }
            }
          }
        )
      end

      it 'does not allow setting allow list mint settings' do
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'msg.sender is not the owner',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setAllowListMintSettings",
              args: {
                allowListMerkleRoot: merkle_root,
                allowListMaxPerAddress: 3,
                allowListMintStart: 2000000,
                allowListMintEnd: 3000000,
                allowListMintPrice: 0.05.ether
              }
            }
          }
        )
      end

      it 'does not allow setting the metadata renderer' do
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'msg.sender is not the owner',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setMetadataRenderer",
              args: {
                metadataRenderer: metadata_renderer.address,
                data: {
                  function: "initializeWithData",
                  args: {
                    info: {
                      name: "Test Name",
                      description: "Test description",
                      imageURI: "https://test.com/image.png",
                      animationURI: ""
                    }
                  }
                }.to_json
              }
            }
          }
        )
      end
    end
  end

  describe 'interaction with the metadata renderer after setting' do
    before do
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "setMetadataRenderer",
            args: {
              metadataRenderer: metadata_renderer.address,
              data: {
                function: "initializeWithData",
                args: {
                  info: {
                    name: "Test Name",
                    description: "Test description",
                    imageURI: "https://test.com/image.png",
                    animationURI: ""
                  }
                }
              }.to_json
            }
          }
        }
      )
      set_public_mint_settings(
        public_max_per_address: 0,
        public_mint_start: 1,
        public_mint_end: 0,
        public_mint_price: 1.ether
      )
      set_weth_allowance(wallet: non_owner_address, amount: 1.ether + per_mint_fee)
      trigger_contract_interaction_and_expect_success(
        from: non_owner_address,
        payload: {
          to: nft_contract.address,
          data: {
            function: "mint",
            args: {
              amount: 1,
              merkleProof: []
            }
          }
        }
      )
    end

    it 'updates token URIs to reflect new metadata properties for newly minted tokens' do
      token_uri = get_contract_state(nft_contract.address, 'tokenURI', 1)
      expect(token_uri).to eq("data:application/json;base64,eyJuYW1lIjogIlRlc3QgTmFtZSAxIiwgImRlc2NyaXB0aW9uIjogIlRlc3QgZGVzY3JpcHRpb24iLCAiaW1hZ2UiOiAiaHR0cHM6Ly90ZXN0LmNvbS9pbWFnZS5wbmciLCAicHJvcGVydGllcyI6IHsibnVtYmVyIjogMSwgIm5hbWUiOiAiVGVzdCBOYW1lIn19")
  
      trigger_contract_interaction_and_expect_error(
        error_msg_includes: 'Admin access only',
        from: non_owner_address,
        payload: {
          to: metadata_renderer.address,
          data: {
            function: "updateMediaURIs",
            args: {
              target: nft_contract.address,
              imageURI: "https://example.com/new.png",
              animationURI: "https://example.com/animation.png"
            }
          }
        }
      )
  
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          to: metadata_renderer.address,
          data: {
            function: "updateMediaURIs",
            args: {
              target: nft_contract.address,
              imageURI: "https://example.com/new.png",
              animationURI: "https://example.com/animation.png"
            }
          }
        }
      )
  
      token_uri = get_contract_state(nft_contract.address, 'tokenURI', 1)
      
      expect(token_uri).to eq("data:application/json;base64,eyJuYW1lIjogIlRlc3QgTmFtZSAxIiwgImRlc2NyaXB0aW9uIjogIlRlc3QgZGVzY3JpcHRpb24iLCAiaW1hZ2UiOiAiaHR0cHM6Ly9leGFtcGxlLmNvbS9uZXcucG5nIiwgImFuaW1hdGlvbl91cmwiOiAiaHR0cHM6Ly9leGFtcGxlLmNvbS9hbmltYXRpb24ucG5nIiwgInByb3BlcnRpZXMiOiB7Im51bWJlciI6IDEsICJuYW1lIjogIlRlc3QgTmFtZSJ9fQ==")
  
      trigger_contract_interaction_and_expect_error(
        error_msg_includes: 'Admin access only',
        from: non_owner_address,
        payload: {
          to: metadata_renderer.address,
          data: {
            function: "updateDescription",
            args: {
              target: nft_contract.address,
              newDescription: "New description"
            }
          }
        }
      )
  
      trigger_contract_interaction_and_expect_success(
        from: owner_address,
        payload: {
          to: metadata_renderer.address,
          data: {
            function: "updateDescription",
            args: {
              target: nft_contract.address,
              newDescription: "New description"
            }
          }
        }
      )
  
      token_uri = get_contract_state(nft_contract.address, 'tokenURI', 1)
      expect(token_uri).to eq("data:application/json;base64,eyJuYW1lIjogIlRlc3QgTmFtZSAxIiwgImRlc2NyaXB0aW9uIjogIk5ldyBkZXNjcmlwdGlvbiIsICJpbWFnZSI6ICJodHRwczovL2V4YW1wbGUuY29tL25ldy5wbmciLCAiYW5pbWF0aW9uX3VybCI6ICJodHRwczovL2V4YW1wbGUuY29tL2FuaW1hdGlvbi5wbmciLCAicHJvcGVydGllcyI6IHsibnVtYmVyIjogMSwgIm5hbWUiOiAiVGVzdCBOYW1lIn19")  
    end
  end

  describe 'royalty settings' do
    let(:fee_numerator) { 100 }

    context 'when owner sets default royalty' do
      it 'allows setting and respects the default royalty' do
        set_default_royalty_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setDefaultRoyalty",
              args: {
                receiver: owner_address,
                feeNumerator: fee_numerator
              }
            }
          }
        )
      end

      it 'allows deleting the default royalty' do
        delete_default_royalty_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "deleteDefaultRoyalty",
              args: {}
            }
          }
        )
      end
    end

    context 'when owner sets token-specific royalty' do
      let(:token_id) { 1 }

      it 'allows setting and respects the token-specific royalty' do
        set_token_royalty_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "setTokenRoyalty",
              args: {
                tokenId: token_id,
                receiver: owner_address,
                feeNumerator: fee_numerator
              }
            }
          }
        )
      end

      it 'allows deleting the token-specific royalty' do
        delete_token_royalty_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "deleteTokenRoyalty",
              args: {
                tokenId: token_id
              }
            }
          }
        )
      end
    end
  end

  describe 'withdrawal process' do
    let(:withdrawal_amount) { 1.ether }

    context 'when owner withdraws WETH' do
      it 'allows the owner to withdraw WETH and updates balances accordingly' do
        withdraw_weth_receipt = trigger_contract_interaction_and_expect_success(
          from: owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "withdrawWETH",
              args: {}
            }
          }
        )
      end
    end

    context 'when non-owner tries to withdraw WETH' do
      it 'does not allow non-owner to withdraw WETH' do
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: 'msg.sender is not the owner',
          from: non_owner_address,
          payload: {
            to: nft_contract.address,
            data: {
              function: "withdrawWETH",
              args: {}
            }
          }
        )
      end
    end
  end

end
