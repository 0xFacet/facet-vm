require 'rails_helper'

describe 'JSONB wrapper' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:alice) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:bob) { "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  let(:daryl) { "0xcccccccccccccccccccccccccccccccccccccccc" }

  before(:all) do
    update_supported_contracts('StorageLayoutTest', 'POpenEditionERC721')
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
    
    token_a.reload
    
    expect(token_a.current_state["getPair"]).to eq({
      "Token A"=>{"Token C"=>"Pair AC", "Token B" => "Pair AB"},
      "Token C"=>{"Token A"=>"Pair AC"},
      "Token B"=>{"Token A" => "Pair AB"},
    })
  end
  
  it 'handles wrapping and persistence correctly' do
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

    wrapper = token_a.wrapper
    
    wrapper.start_transaction
    expect(wrapper.read("balanceOf", user_address).value).to eq(0)
    expect(wrapper.read("decimals").value).to eq(18)
    expect(wrapper.read("name").value).to eq("Token A")

    new_balance = 1000
    wrapper.write("balanceOf", user_address, TypedVariable.create(:uint256, new_balance))
    expect(wrapper.read("balanceOf", user_address).value).to eq(new_balance)

    new_decimals = 8
    wrapper.write('decimals', TypedVariable.create(:uint8, new_decimals))
    expect(wrapper.read("decimals").value).to eq(new_decimals)

    expect(wrapper.read("allowance", user_address, alice).value).to eq(0)

    new_allowance = 100
    wrapper.write("allowance", user_address, alice, TypedVariable.create(:uint256, new_allowance))
    expect(wrapper.read("allowance", user_address, alice).value).to eq(new_allowance)

    # Commit the first transaction
    wrapper.commit_transaction

    # Start a second transaction and simulate failure
    wrapper.start_transaction
    wrapper.write("balanceOf", user_address, TypedVariable.create(:uint256, new_balance + 500))
    expect(wrapper.read("balanceOf", user_address).value).to eq(new_balance + 500)

    # Simulate a transaction failure
    wrapper.rollback_transaction

    # Ensure the state has not been changed by the failed transaction
    expect(wrapper.read("balanceOf", user_address).value).to eq(new_balance)
    expect(wrapper.read("decimals").value).to eq(new_decimals)
    expect(wrapper.read("allowance", user_address, alice).value).to eq(new_allowance)

    # Start a third transaction
    wrapper.start_transaction
    new_allowance2 = 200
    wrapper.write("allowance", user_address, alice, TypedVariable.create(:uint256, new_allowance2))
    expect(wrapper.read("allowance", user_address, alice).value).to eq(new_allowance2)

    wrapper.commit_transaction
    wrapper.persist(EthBlock.max_processed_block_number + 1000)

    token_a.reload
    state = token_a.current_state

    expect(state["balanceOf"].dig(user_address)).to eq(new_balance)
    expect(state["decimals"]).to eq(new_decimals)
    expect(state["allowance"].dig(user_address, alice)).to eq(new_allowance2)
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        op: :call,
        data: {
          to: token_a_address,
          function: "changeName",
          args: { name: "Token A NEW" }
        }
      }
    )
    
    token_a.reload
    
    state = token_a.current_state
    expect(state["name"]).to eq("Token A NEW")
    
    res = ContractTransaction.make_static_call(
      contract: token_a.address,
      function_name: "getName"
    )
    
    expect(res).to eq("Token A NEW")
    
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
    
    expect(token_a.reload.current_state["balanceOf"].dig(user_address)).to eq(1000)
  end

  it 'handles block-level rollback (reorg)' do
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

    wrapper = token_a.wrapper

    # Start a transaction and commit it
    wrapper.start_transaction
    new_balance = 1000
    new_decimals = 8
    new_allowance = 100

    wrapper.write("balanceOf", user_address, TypedVariable.create(:uint256, new_balance))
    wrapper.write("decimals", TypedVariable.create(:uint8, new_decimals))
    
    wrapper.write("allowance", user_address, alice, TypedVariable.create(:uint256, new_allowance))
    wrapper.commit_transaction
    wrapper.persist(EthBlock.max_processed_block_number + 1)

    # Start another transaction and commit it
    wrapper.start_transaction
    new_balance2 = 2000
    new_decimals2 = 9
    new_allowance2 = 200

    wrapper.write("balanceOf", user_address, TypedVariable.create(:uint256, new_balance2))
    wrapper.write("decimals", TypedVariable.create(:uint8, new_decimals2))
    wrapper.write("allowance", user_address, alice, TypedVariable.create(:uint256, new_allowance2))
    wrapper.commit_transaction
    wrapper.persist(EthBlock.max_processed_block_number + 2)
    
    wrapper.rollback_to_block(EthBlock.max_processed_block_number + 1)

    token_a.reload
    state = token_a.current_state

    expect(state["balanceOf"].dig(user_address)).to eq(new_balance)
    expect(state["decimals"]).to eq(new_decimals)
    expect(state["allowance"].dig(user_address, alice)).to eq(new_allowance)
  end

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
          type: "POpenEditionERC721",
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
  
  it 'handles multiple modifications to the same nested allowance mapping' do
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

    wrapper = token_a.wrapper

    wrapper.start_transaction

    expect(wrapper.read("balanceOf", user_address).value).to eq(0)
    expect(wrapper.read("decimals").value).to eq(18)
    expect(wrapper.read("name").value).to eq("Token A")

    new_allowance = 100
    wrapper.write("allowance", user_address, alice, TypedVariable.create(:uint256, new_allowance))
    expect(wrapper.read("allowance", user_address, alice).value).to eq(new_allowance)

    new_allowance2 = 200
    wrapper.write("allowance", user_address, bob, TypedVariable.create(:uint256, new_allowance2))
    expect(wrapper.read("allowance", user_address, bob).value).to eq(new_allowance2)

    wrapper.commit_transaction
    wrapper.persist(EthBlock.max_processed_block_number + 1)

    token_a.reload
    state = token_a.current_state

    expect(state["allowance"].dig(user_address, alice)).to eq(new_allowance)
    expect(state["allowance"].dig(user_address, bob)).to eq(new_allowance2)
  end
  
  it 'handles arrays' do
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

    wrapper = token_a.wrapper

    wrapper.start_transaction
    
    expect(wrapper.read("testArrayFixedLength", 0).value).to eq(0)
    
    expect { wrapper.read("testArrayFixedLength", 1000) }.to raise_error(IndexError)
    expect { wrapper.read("testArrayVariableLength", 0) }.to raise_error(IndexError)

    wrapper.write("testArrayFixedLength", 0, TypedVariable.create(:uint256, 100))
    wrapper.write("testArrayVariableLength", 0, TypedVariable.create(:uint256, 200))
    
    expect(wrapper.read("testArrayFixedLength", 0).value).to eq(100)
    expect(wrapper.read("testArrayVariableLength", 0).value).to eq(200)

    wrapper.commit_transaction
    
    save_block = EthBlock.max_processed_block_number + 1
    
    wrapper.persist(save_block)

    token_a.reload
    state = token_a.current_state
   
    expect(state["testArrayFixedLength"][0]).to eq(100)
    expect(state["testArrayVariableLength"][0]).to eq(200)
    
    wrapper.rollback_to_block(save_block - 1)
    
    token_a.reload
    state = token_a.current_state
    
    expect(state["testArrayFixedLength"]).to eq([])
    expect(state["testArrayVariableLength"]).to eq([])
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        op: :call,
        data: {
          to: token_a_address,
          function: "pushTest",
          args: { value: 100 }
        }
      }
    )
    
    expect(token_a.reload.current_state["testArrayVariableLength"]).to eq([100])
    
    ret_val = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        op: :call,
        data: {
          to: token_a_address,
          function: "popTest",
          args: {}
        }
      }
    ).return_value
    
    expect(ret_val).to eq(100)
    expect(token_a.reload.current_state["testArrayVariableLength"]).to eq([])
  end
end
