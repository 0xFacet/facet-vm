require 'rails_helper'

RSpec.describe StateManager, type: :model do
  let!(:user_address) { "0x000000000000000000000000000000000000000a" }
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:daryl) { "0xcccccccccccccccccccccccccccccccccccccccc" }
  let!(:token_a) {
    
    tokenA_deploy_receipt = trigger_contract_interaction_and_expect_success(
      from: "0x" + SecureRandom.hex(20),
      payload: {
        to: nil,
        data: {
          type: "StorageLayoutTest",
          args: { name: "Token A" }
        }
      }
    )
    token_a_address = tokenA_deploy_receipt.address
    token_a = tokenA_deploy_receipt.contract
  }
  
  let!(:contract_address) { token_a.address }
  let!(:state_var_layout) {
    {
      "name" => Type.new(:string),
      "symbol" => Type.new(:string),
      "decimals" => Type.new(:uint8),
      "totalSupply" => Type.new(:uint256),
      "balanceOf" => Type.new(:mapping, key_type: Type.new(:address), value_type: Type.new(:uint256)),
      "allowance" => Type.new(:mapping, key_type: Type.new(:address), value_type: Type.new(:mapping, key_type: Type.new(:address), value_type: Type.new(:uint256))),
      "testArray" => Type.new(:array, value_type: Type.new(:uint256)),
      "testArrayFixed" => Type.new(:array, value_type: Type.new(:string), length: 3)
    }
  }
  let!(:state_manager) { StateManager.new(contract_address, state_var_layout, skip_state_save: true) }
  let!(:storage_pointer) { StoragePointer.new(state_manager) }
  
  let(:start_block) { EthBlock.max_processed_block_number + 1 }
  
  let!(:address1) { TypedVariable.create(:address, "0x0000000000000000000000000000000000000001")}
  let!(:address2) { TypedVariable.create(:address, "0x0000000000000000000000000000000000000002")}
  
  before(:all) do
    update_supported_contracts(
      'StorageLayoutTest',
      'OpenEditionERC721',
      'StateStructureTest'
    )
  end

  class Integer
    def t
      TypedVariable.create(:uint256, self)
    end
  end
  
  describe "basic state management" do
    it 'handles live transaction rollback' do
      contract = trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: :create,
          data: {
            type: "StorageLayoutTest",
            args: { name: "Token A" }
          }
        }
      )
      
      target = trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: :create,
          data: {
            type: "StorageLayoutTest",
            args: { name: "Token B" }
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
      
      in_block do |c|
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
      
      ts = ContractTransaction.make_static_call(
        contract: nft.address,
        function_name: "totalSupply",
        function_args: {}
      )
      
      expect(ts).to eq(7)
    end
    
    
    it 'handles default values' do
      tokenA_deploy_receipt = trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          to: nil,
          data: {
            type: "StorageLayoutTest",
            args: { name: "Token A" }
          }
        }
      )
      token_a_address = tokenA_deploy_receipt.address
      token_a = tokenA_deploy_receipt.contract
      
      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          op: :call,
          data: {
            to: token_a_address,
            function: "updateBalance",
            args: { amount: 1000 }
          }
        }
      )
      Contract.cache_all_state
      expect(token_a.reload.current_state["balanceOf"]).to eq({user_address => 1000})
      
      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          op: :call,
          data: {
            to: token_a_address,
            function: "updateBalance",
            args: { amount: 0 }
          }
        }
      )
      Contract.cache_all_state
      expect(token_a.reload.current_state["balanceOf"]).to eq({})
    end
     
    it 'handles getPair case' do
      tokenA_deploy_receipt = trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          to: nil,
          data: {
            type: "StorageLayoutTest",
            args: { name: "Token A" }
          }
        }
      )
      token_a_address = tokenA_deploy_receipt.address
      token_a = tokenA_deploy_receipt.contract
      
      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          op: :call,
          data: {
            to: token_a_address,
            function: "addPair",
            args: ["Token A", "Token B", "Pair AB"]
          }
        }
      )
      
      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          op: :call,
          data: {
            to: token_a_address,
            function: "addPair",
            args: ["Token A", "Token C", "Pair AC"]
          }
        }
      )
      Contract.cache_all_state
      token_a.reload
      
      expect(token_a.current_state["getPair"]).to eq({
        "Token A"=>{"Token C"=>"Pair AC", "Token B" => "Pair AB"},
        "Token C"=>{"Token A"=>"Pair AC"},
        "Token B"=>{"Token A" => "Pair AB"},
      })
    end
    
    it "sets and gets values" do
      state_manager.set("name", TypedVariable.create(:string, "Token A"))
      expect(state_manager.get("name").value).to eq("Token A")

      state_manager.set("decimals", TypedVariable.create(:uint8, 18))
      expect(state_manager.get("decimals").value).to eq(18)
    end

    it "handles nested mappings" do
      state_manager.set("balanceOf", address1, TypedVariable.create(:uint256, 1000))
      expect(state_manager.get("balanceOf", address1).value).to eq(1000)

      state_manager.set("allowance", address1, address2, TypedVariable.create(:uint256, 500))
      expect(state_manager.get("allowance", address1, address2).value).to eq(500)
      # ap token_a.address
    end

    it "handles array operations" do
      # ap token_a.address
      # binding.pry
      # ap contract_address
      block_number = start_block
      
      # Push elements into the array
      state_manager.array_push("testArray", TypedVariable.create(:uint256, 42))
      state_manager.array_push("testArray", TypedVariable.create(:uint256, 43))
      expect(state_manager.array_length("testArray").value).to eq(2)
      expect(state_manager.get("testArray", 0.t).value).to eq(42)
      expect(state_manager.get("testArray", 1.t).value).to eq(43)
  
      # Pop an element from the array
      expect(state_manager.array_pop("testArray").value).to eq(43)
      expect(state_manager.array_length("testArray").value).to eq(1)
      expect(state_manager.get("testArray", 0.t).value).to eq(42)
      state_manager.apply_transaction
      
      # Save the block changes
      state_manager.save_block_changes(block_number)
      block_number += 1
      
      # Push another element
      state_manager.array_push("testArray", TypedVariable.create(:uint256, 44))
      state_manager.apply_transaction
      state_manager.save_block_changes(block_number)
      block_number += 1
      
      expect(state_manager.array_length("testArray").value).to eq(2)
      expect(state_manager.get("testArray", 0.t).value).to eq(42)
      expect(state_manager.get("testArray", 1.t).value).to eq(44)
  
      # Remove an element directly
      state_manager.set("testArray", 0.t, TypedVariable.create(:uint256, 0))
      state_manager.apply_transaction
      state_manager.save_block_changes(block_number)
      block_number += 1
      
      expect(state_manager.array_length("testArray").value).to eq(2)
      expect(state_manager.get("testArray", 0.t).value).to eq(0)
  
      # Rollback to previous block where element was 42 and 44
      
      state_manager.rollback_to_block(start_block + 1)
      state_manager.reload_state
      
      expect(state_manager.array_length("testArray").value).to eq(2)
      expect(state_manager.get("testArray", 0.t).value).to eq(42)
      expect(state_manager.get("testArray", 1.t).value).to eq(44)
      
      # Rollback to the initial block where element was only 42
      state_manager.rollback_to_block(start_block)
      state_manager.reload_state
      expect(state_manager.array_length("testArray").value).to eq(1)
      expect(state_manager.get("testArray", 0.t).value).to eq(42)
      
      expect(state_manager.get("testArrayFixed", 0.t).value).to eq("")
      state_manager.set("testArrayFixed", 1.t, TypedVariable.create(:string, "hi"))
      
      expect(state_manager.get("testArrayFixed", 1.t).value).to eq("hi")
      
      expect(state_manager.get("testArrayFixed", 2.t).value).to eq("")

      expect {
        state_manager.get("testArrayFixed", 10.t)
      }.to raise_error(IndexError)
      
      expect {
        state_manager.get("testArray", 10.t)
      }.to raise_error(IndexError)
      
      expect {
        state_manager.set("testArray", 10.t, TypedVariable.create(:uint256, 100))
      }.to raise_error(IndexError)
      
      expect {
        state_manager.set("testArrayFixed", 3.t, TypedVariable.create(:string, "hi"))
      }.to raise_error(IndexError)
    end

    it "handles deletions and default values" do
      # ap contract_address
      state_manager.set("name", TypedVariable.create(:string, "Token A"))
      expect(state_manager.get("name").value).to eq("Token A")

      state_manager.set("name", TypedVariable.create(:string, ""))
      expect(state_manager.get("name").value).to eq("")

      state_manager.set("balanceOf", address1, TypedVariable.create(:uint256, 1000))
      expect(state_manager.get("balanceOf", address1).value).to eq(1000)

      state_manager.set("balanceOf", address1, TypedVariable.create(:uint256, 0))
      expect(state_manager.get("balanceOf", address1).value).to eq(0)
    end

    it "persists state changes" do
      # ap contract_address
      state_manager.set("name", TypedVariable.create(:string, "Token A"))
      state_manager.set("decimals", TypedVariable.create(:uint8, 18))
      state_manager.set("balanceOf", address1, TypedVariable.create(:uint256, 1000))
      state_manager.apply_transaction

      block_number = start_block
      state_manager.save_block_changes(block_number)

      persisted_state = NewContractState.where(contract_address: contract_address).pluck(:key, :value).to_h
      
      expect(persisted_state.keys).to include(["name"], ["decimals"], ["balanceOf",  address1.as_json])
      expect(persisted_state[["name"]]).to eq("Token A")
      expect(persisted_state[["decimals"]]).to eq(18)
      expect(persisted_state[["balanceOf", address1.as_json]]).to eq(1000)
    end

    it "handles rollbacks" do
      state_manager.set("name", TypedVariable.create(:string, "Token Z"))
      state_manager.set("symbol", TypedVariable.create(:string, "Z"))
      state_manager.set("decimals", TypedVariable.create(:uint8, 50))
      state_manager.apply_transaction

      block_number = start_block
      state_manager.save_block_changes(block_number)

      state_manager.set("name", TypedVariable.create(:string, "Token Q"))
      state_manager.set("symbol", TypedVariable.create(:string, "Q"))
      state_manager.set("decimals", TypedVariable.create(:uint8, 66))
      state_manager.apply_transaction

      block_number += 1
      state_manager.save_block_changes(block_number)
      
      state_manager.rollback_to_block(start_block)
      
      expect(state_manager.get("name").value).to eq("Token Z")
      expect(state_manager.get("symbol").value).to eq("Z")
      expect(state_manager.get("decimals").value).to eq(50)
      
      live_state = NewContractState.load_state_as_hash(contract_address)
      
      expected_state = {
        ["name"] => "Token Z",
        ["symbol"] => "Z",
        ["decimals"] => 50
      }
      
      expect(live_state).to eq(expected_state)
    end
    
    it "reverts changes within the block without saving to db" do
      state_manager.set("name", TypedVariable.create(:string, "Token A"))
      state_manager.set("decimals", TypedVariable.create(:uint8, 18))
      state_manager.apply_transaction

      expect(state_manager.get("name").value).to eq("Token A")
      expect(state_manager.get("decimals").value).to eq(18)

      state_manager.set("name", TypedVariable.create(:string, "Token B"))
      state_manager.set("decimals", TypedVariable.create(:uint8, 8))

      expect(state_manager.get("name").value).to eq("Token B")
      expect(state_manager.get("decimals").value).to eq(8)

      state_manager.rollback_transaction

      expect(state_manager.get("name").value).to eq("Token A")
      expect(state_manager.get("decimals").value).to eq(18)
    end
    
    it 'handles intra-tx updates' do
      target = trigger_contract_interaction_and_expect_success(
        from: alice,
        payload: {
          op: :create,
          data: {
            type: "StorageLayoutTest",
            args: { name: "Token A" }
          }
        }
      ).contract
      
      end_balance = nil
      
      in_block do |c|
        c.trigger_contract_interaction_and_expect_success(
          from: target.address,
          payload: {
            op: :call,
            data: {
              to: target.address,
              function: "updateBalance",
              args: 1000
            }
          }
        )
        
        target.reload.state_manager
        
        c.trigger_contract_interaction_and_expect_success(
          from: target.address,
          payload: {
            op: :call,
            data: {
              to: target.address,
              function: "updateBalance",
              args: 0
            }
          }
        )
        
        c.trigger_contract_interaction_and_expect_success(
          from: target.address,
          payload: {
            op: :call,
            data: {
              to: target.address,
              function: "testUpdate"
            }
          }
        )
      end
      
      ts = ContractTransaction.make_static_call(
        contract: target.address,
        function_name: "balanceOf",
        function_args: target.address
      )

      expect(ts).to eq(100)
    end
    
    it "supports structs" do
      layout = {
        "upgradeAdmin" => Type.new(:address),
        "tokenUpgradeLevelsByCollection" => Type.new(
          :mapping,
          key_type: Type.new(:address),
          value_type: Type.new(
            :array,
            value_type: Type.new(
              :struct,
              struct_definition: StructDefinition.new(:TokenUpgradeLevel) do
                string :name
                string :imageURI
                string :animationURI
                string :extraAttributesJson
                uint256 :startTime
                uint256 :endTime
              end
            )
          )
        ),
        "tokenStatusByCollection" => Type.new(
          :mapping,
          key_type: Type.new(:address),
          value_type: Type.new(
            :mapping,
            key_type: Type.new(:uint256),
            value_type: Type.new(
              :struct,
              struct_definition: StructDefinition.new(:TokenStatus) do
                uint256 :upgradeLevel
                uint256 :lastUpgradeTime
              end
            )
          )
        ),
        "contractInfoByCollection" => Type.new(
          :mapping,
          key_type: Type.new(:address),
          value_type: Type.new(
            :struct,
            struct_definition: StructDefinition.new(:ContractInfo) do
              string :name
              string :description
              string :imageURI
            end
          )
        ),
        "perUpgradeFee" => Type.new(:uint256),
        "feeTo" => Type.new(:address),
        "WETH" => Type.new(:address),
        "maxUpgradeLevelCount" => Type.new(:uint256)
      }
      
      state_manager = StateManager.new(contract_address, layout, skip_state_save: true)
      # binding.pry
      state_manager.set("contractInfoByCollection", alice, "name", TypedVariable.create(:string, "Example Contract"))
      state_manager.set("contractInfoByCollection", alice, "description", TypedVariable.create(:string, "A sample contract description."))
      state_manager.set("contractInfoByCollection", alice, "imageURI", TypedVariable.create(:string, "https://example.com/image.png"))

      expect(state_manager.get("contractInfoByCollection", alice, "name").value).to eq("Example Contract")
      expect(state_manager.get("contractInfoByCollection", alice, "description").value).to eq("A sample contract description.")
      expect(state_manager.get("contractInfoByCollection", alice, "imageURI").value).to eq("https://example.com/image.png")
      
      state_manager.set("contractInfoByCollection", alice, "name", TypedVariable.create(:string, "Example Contract"))
      state_manager.set("contractInfoByCollection", alice, "description", TypedVariable.create(:string, "A sample contract description."))
      state_manager.set("contractInfoByCollection", alice, "imageURI", TypedVariable.create(:string, "https://example.com/image.png"))

      struct_pointer = StoragePointer.new(state_manager, ["contractInfoByCollection", alice])
      # binding.pry
      struct_hash = struct_pointer.load_struct.as_json

      expect(struct_hash["name"]).to eq("Example Contract")
      expect(struct_hash["description"]).to eq("A sample contract description.")
      expect(struct_hash["imageURI"]).to eq("https://example.com/image.png")
      
      # struct_value = StructVariable.new(
      #   :ContractInfo,
      #   {
      #     "name" => TypedVariable.create(:string, "Example Contract"),
      #     "description" => TypedVariable.create(:string, "A sample contract description."),
      #     "imageURI" => TypedVariable.create(:string, "https://example.com/image.png")
      #   }
      # )

      # struct_pointer = StoragePointer.new(state_manager, ["contractInfoByCollection", "0x5678"])
      # struct_pointer.set_struct(struct_value)

      # expect(state_manager.get("contractInfoByCollection", alice, "name").value).to eq("Example Contract")
      # expect(state_manager.get("contractInfoByCollection", alice, "description").value).to eq("A sample contract description.")
      # expect(state_manager.get("contractInfoByCollection", alice, "imageURI").value).to eq("https://example.com/image.png")
      
      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          op: :call,
          data: {
            to: token_a.address,
            function: "setStructName",
            args: "Struct Test"
          }
        }
      )
      
      ts = ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "tokenUpgradeLevelInstance",
      )
      expect(ts['name']).to eq("Struct Test")
    end
  end
  
  describe "build_structure" do
    it "builds a nested structure from key-value pairs" do
      contract = trigger_contract_interaction_and_expect_success(
        from: "0x" + SecureRandom.hex(20),
        payload: {
          to: nil,
          data: {
            type: "StateStructureTest",
            args: { alice: alice, bob: bob }
          }
        }
      ).contract
      
      expected_structure = {
        "name" => "Token A",
        "decimals" => 18,
        "balanceOf" => {
          alice => 1000
        },
        "allowance" => {
          alice => {
            bob => 500
          }
        },
        "testArray" => [0, 42, 43, 0, 1, 0],
        "testArrayFixed" => ['', 'hi', ''],
        "ownerOf" => {
          "1" => alice,
          "2" => bob
        },
        "jim" => {
          "name" => "Jim",
          "age" => 100
        },
        "jimExtended" => {
          "name" => "Jim",
          "age" => 100
        },
        "blank" => {},
        "peopleFixed" => [{}, {"age"=>30, "name"=>"Alice"}, {}],
        "peopleVariable" => [{}, {"age"=>30, "name"=>"Alice"}, {}, {"age"=>31, "name"=>"Bob"}, {}],
        "peopleMap" => {"Jim"=>{"age"=>100, "name"=>"Jim"}},
      }
      
      result = contract.state_manager.build_structure
      
      expect(result).to eq(expected_structure)
    end
  end
  
  describe "StoragePointer" do
    it "sets and gets values using pointer" do
      storage_pointer["name"] = TypedVariable.create(:string, "Token A")
      expect(storage_pointer["name"].value).to eq("Token A")

      storage_pointer["decimals"] = TypedVariable.create(:uint8, 18)
      expect(storage_pointer["decimals"].value).to eq(18)
    end

    it "handles nested mappings using pointer" do
      storage_pointer["balanceOf"][address1] = TypedVariable.create(:uint256, 1000)
      expect(storage_pointer["balanceOf"][address1].value).to eq(1000)

      storage_pointer["allowance"][address1][address2] = TypedVariable.create(:uint256, 500)
      expect(storage_pointer["allowance"][address1][address2].value).to eq(500)
    end

    it "handles array operations using pointer" do
      block_number = start_block
      
      # Push elements into the array using pointer
      storage_pointer["testArray"].push(TypedVariable.create(:uint256, 42))
      storage_pointer["testArray"].push(TypedVariable.create(:uint256, 43))
      expect(storage_pointer["testArray"].length.value).to eq(2)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      expect(storage_pointer["testArray"][1.t].value).to eq(43)
  
      # Pop an element from the array using pointer
      expect(storage_pointer["testArray"].pop.value).to eq(43)
      expect(storage_pointer["testArray"].length.value).to eq(1)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      state_manager.apply_transaction
      
      # Save the block changes
      state_manager.save_block_changes(block_number)
      block_number += 1
      
      # Push another element using pointer
      storage_pointer["testArray"].push(TypedVariable.create(:uint256, 44))
      state_manager.apply_transaction
      state_manager.save_block_changes(block_number)
      block_number += 1
      
      expect(storage_pointer["testArray"].length.value).to eq(2)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      expect(storage_pointer["testArray"][1.t].value).to eq(44)
  
      # Remove an element directly using pointer
      storage_pointer["testArray"][0.t] = TypedVariable.create(:uint256, 0)
      state_manager.apply_transaction
      state_manager.save_block_changes(block_number)
      block_number += 1
      
      expect(storage_pointer["testArray"].length.value).to eq(2)
      expect(storage_pointer["testArray"][0.t].value).to eq(0)
      
      # Rollback to previous block where element was 42 and 44
      state_manager.rollback_to_block(block_number - 2)
      state_manager.reload_state
      
      expect(storage_pointer["testArray"].length.value).to eq(2)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      expect(storage_pointer["testArray"][1.t].value).to eq(44)
      
      # Rollback to the initial block where element was only 42
      state_manager.rollback_to_block(start_block)
      state_manager.reload_state
      expect(storage_pointer["testArray"].length.value).to eq(1)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      
      storage_pointer["testArray"].push(TypedVariable.create(:uint256, 0))
      
      state_manager.apply_transaction
      state_manager.save_block_changes(100)
      
      state_manager.reload_state
      
      expect(storage_pointer["testArray"].length.value).to eq(2)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      expect(storage_pointer["testArray"][1.t].value).to eq(0)
      
      storage_pointer["testArray"].push(TypedVariable.create(:uint256, 110))
      storage_pointer["testArray"].push(TypedVariable.create(:uint256, 0))
      
      state_manager.apply_transaction
      state_manager.save_block_changes(101)
      
      state_manager.reload_state
      
      expect(storage_pointer["testArray"].length.value).to eq(4)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      expect(storage_pointer["testArray"][1.t].value).to eq(0)
      expect(storage_pointer["testArray"][2.t].value).to eq(110)
      expect(storage_pointer["testArray"][3.t].value).to eq(0)
      
      expect(state_manager.build_structure['testArray']).to eq([42, 0, 110, 0])
      
      storage_pointer["testArray"].pop
      
      state_manager.apply_transaction
      state_manager.save_block_changes(102)
      
      state_manager.reload_state
      
      expect(storage_pointer["testArray"].length.value).to eq(3)
      expect(storage_pointer["testArray"][0.t].value).to eq(42)
      expect(storage_pointer["testArray"][1.t].value).to eq(0)
      expect(storage_pointer["testArray"][2.t].value).to eq(110)
      
      expect(state_manager.build_structure['testArray']).to eq([42, 0, 110])
    end
  end
end
