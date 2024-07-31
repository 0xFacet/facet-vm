require 'rails_helper'

describe 'Reorg handling' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  
  before(:all) do
    update_supported_contracts("StubERC20")
  end
  
  def p1_setup
    token_a = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: { data: { type: "StubERC20", args: "Token A" } }
    ).contract
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_a.address,
        data: {
          function: "mint",
          args: {
            amount: 100.ether
          }
        }
      }
    ).contract
  end
  
  def p2_setup
    token_b = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: { data: { type: "StubERC20", args: "Token B" } }
    ).contract
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_b.address,
        data: {
          function: "mint",
          args: {
            amount: 22.ether
          }
        }
      }
    ).contract
  end
  
  it 'handles reorgs' do
    start_block = EthBlock.max_processed_block_number
    
    token_a = p1_setup
    
    pt1_block = EthBlock.max_processed_block_number
    
    p1_a_total_supply = ContractTransaction.make_static_call(
      contract: token_a.address,
      function_name: "totalSupply"
    )
    
    expect(p1_a_total_supply).to eq(100.ether)
    expect(Contract.count).to eq(1)
    expect(TransactionReceipt.count).to eq(2)
    
    ContractBlockChangeLog.rollback_all_changes(start_block)
    
    expect(Contract.count).to eq(0)
    expect(TransactionReceipt.count).to eq(0)
    
    expect {
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "totalSupply"
      )
    }.to raise_error(/Contract not found/)
    
    token_a = p1_setup
    
    block = EthBlock.max_processed_block_number
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_a.address,
        data: {
          function: "updateName",
          args: {
            name: "New Token A"
          }
        }
      }
    ).contract
    
    expect(Contract.count).to eq(1)
    
    expect(
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "name"
      )
    ).to eq("New Token A")
    
    token_b = p2_setup
    
    expect(Contract.count).to eq(2)
    
    ContractBlockChangeLog.rollback_all_changes(block)
    
    expect(
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "name"
      )
    ).to eq("Token A")
    
    expect {
      ContractTransaction.make_static_call(
        contract: token_b.address,
        function_name: "name"
      )
    }.to raise_error(/Contract not found/)
    
    expect(Contract.count).to eq(1)
    expect(TransactionReceipt.count).to eq(2)
    
    ContractBlockChangeLog.rollback_all_changes(start_block)
    
    expect(Contract.count).to eq(0)
    expect(TransactionReceipt.count).to eq(0)
    
    expect {
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "totalSupply"
      )
    }.to raise_error(/Contract not found/)
    
    token_a = p1_setup
    token_b = p2_setup
    
    block = EthBlock.max_processed_block_number
    
    state_manager = token_a.state_manager
    
    state_manager.start_transaction
    state_manager.set("name", TypedVariable.create(:string, "Set by state manager"))
    state_manager.apply_transaction
    state_manager.save_block_changes(EthBlock.max_processed_block_number + 1)
    
    expect(
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "name"
      )
    ).to eq("Set by state manager")
    
    ContractBlockChangeLog.rollback_all_changes(block)
    
    expect(
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "name"
      )
    ).to eq("Token A")
    
    state_manager.start_transaction
    state_manager.set("name", TypedVariable.create(:string, "Set again"))
    state_manager.apply_transaction
    
    expect {
      state_manager.save_block_changes(EthBlock.max_processed_block_number + 1)
    }.to raise_error(/Contract state lock version mismatch/)
    
    state_manager.start_transaction
    state_manager.set("name", TypedVariable.create(:string, "Set again"))
    state_manager.apply_transaction
    state_manager.save_block_changes(EthBlock.max_processed_block_number + 1)
    
    expect(
      ContractTransaction.make_static_call(
        contract: token_a.address,
        function_name: "name"
      )
    ).to eq("Set again")
    
    
    state_manager.save_block_changes(EthBlock.max_processed_block_number + 1)
  end
  
  it 'handles concurrent execution' do
    to_block = 100

    pid1 = fork do
      ActiveRecord::Base.connection.reconnect!
      ContractBlockChangeLog.rollback_all_changes(to_block) do
        sleep 3 # Simulate a delay to force a conflict
      end
    end

    pid2 = fork do
      sleep 1 # Ensure this process starts after the first one
      ActiveRecord::Base.connection.reconnect!
      expect {
        ContractBlockChangeLog.rollback_all_changes(to_block)
      }.to raise_error(ActiveRecord::StatementInvalid, /could not obtain lock/)
    rescue PG::LockNotAvailable
      puts "Lock not available"
    end

    Process.wait(pid1)
    Process.wait(pid2)
    
    pid1 = fork do
      ActiveRecord::Base.connection.reconnect!
      ContractBlockChangeLog.rollback_all_changes(to_block)
    end

    pid2 = fork do
      sleep 3
      ContractBlockChangeLog.rollback_all_changes(to_block)
    end

    Process.wait(pid1)
    Process.wait(pid2)
  end
  
  it 'handles historical contract state' do
    token_a = p1_setup
    
    start_block = EthBlock.max_processed_block_number
    
    start_supply = ContractTransaction.make_static_call(
      contract: token_a.address,
      function_name: "totalSupply"
    )
    
    start_balance = ContractTransaction.make_static_call(
      contract: token_a.address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_a.address,
        data: {
          function: "mint",
          args: {
            amount: 22.ether
          }
        }
      }
    )
    
    expect(
      ContractBlockChangeLog.historical_value(
        token_a.address, "totalSupply", start_block
      )
    ).to eq(start_supply)
    
    expect(
      ContractBlockChangeLog.historical_value(
        token_a.address, ["balanceOf", user_address], start_block
      )
    ).to eq(start_balance)

    cp1 = EthBlock.max_processed_block_number
    
    cp1_balance = ContractTransaction.make_static_call(
      contract: token_a.address,
      function_name: "balanceOf",
      function_args: user_address
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_a.address,
        data: {
          function: "mint",
          args: {
            amount: 1.ether
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: token_a.address,
        data: {
          function: "updateName",
          args: {
            name: "New Token A"
          }
        }
      }
    )
    
    expect(
      ContractBlockChangeLog.historical_value(
        token_a.address, ["balanceOf", user_address], cp1
      )
    ).to eq(cp1_balance)
    
    expect(
      ContractBlockChangeLog.historical_state(
        token_a.address, cp1
      )[["balanceOf", user_address]]
    ).to eq(cp1_balance)
    
    expect(
      ContractBlockChangeLog.historical_value(
        token_a.address, "name", cp1 + 1
      )
    ).to eq("Token A")
    
    expect(
      ContractBlockChangeLog.historical_value(
        token_a.address, "name", EthBlock.max_processed_block_number
      )
    ).to eq("New Token A")
  end
end
