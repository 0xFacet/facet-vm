require 'rails_helper'

RSpec.describe Contract, type: :model do
  before do
    block = EthBlock.order(imported_at: :desc).first
    
    block_number = block&.block_number.to_i + 1
    
    blockhash = "0x" + SecureRandom.hex(32)

    EthBlock.create!(
      block_number: block_number,
      blockhash: blockhash,
      parent_blockhash: block&.blockhash || "0x" + SecureRandom.hex(32),
      timestamp: Time.zone.now.to_i,
      imported_at: Time.zone.now,
      processing_state: "complete"
    )
    
    @ethscription = Ethscription.create!(
      ethscription_id: '0x' + SecureRandom.hex(32),
      block_number: block_number,
      block_blockhash: '0x' + SecureRandom.hex(32),
      transaction_index: 1,
      creator: '0x' + SecureRandom.hex(20),
      initial_owner: '0x' + SecureRandom.hex(20),
      current_owner: '0x' + SecureRandom.hex(20),
      creation_timestamp: Time.now,
      content_uri: "data:,hi",
      content_sha: SecureRandom.hex(32),
      mimetype: 'text/plain',
      created_at: Time.now,
      updated_at: Time.now
    )
    
    @ethscription2 = Ethscription.create!(
      ethscription_id: '0x' + SecureRandom.hex(32),
      block_number: block_number,
      block_blockhash: '0x' + SecureRandom.hex(32),
      transaction_index: 2,
      creator: '0x' + SecureRandom.hex(20),
      initial_owner: '0x' + SecureRandom.hex(20),
      current_owner: '0x' + SecureRandom.hex(20),
      creation_timestamp: Time.now,
      content_uri: "data:,hi",
      content_sha: SecureRandom.hex(32),
      mimetype: 'text/plain',
      created_at: Time.now,
      updated_at: Time.now
    )

    @contract = Contract.create!(
      transaction_hash: @ethscription.ethscription_id,
      current_type: 'SomeType',
      current_init_code_hash: SecureRandom.hex(32),
      created_at: Time.now,
      updated_at: Time.now,
      address: '0x' + SecureRandom.hex(20),
      current_state: {}
    )
  end

  context 'when a ContractState is created' do
    it 'updates the current_state of the Contract' do
      new_state = { key: 'value' }
      ContractState.create!(
        transaction_hash: @ethscription.ethscription_id,
        state: new_state,
        type: @contract.current_type,
        init_code_hash: @contract.current_init_code_hash,
        block_number: 1,
        transaction_index: 1,
        created_at: Time.now,
        updated_at: Time.now,
        contract_address: @contract.address,
      )

      @contract.reload
      expect(@contract.current_state).to eq(new_state.stringify_keys)
    end
  end

  context 'when a ContractState is deleted' do
    counter = 0
    
    it 'updates the current_state of the Contract' do
      old_state = { key: 'old_value' }
      
      ContractState.create!(
        transaction_hash: @ethscription.ethscription_id,
        state: old_state,
        type: @contract.current_type,
        init_code_hash: @contract.current_init_code_hash,
        block_number: counter += 1,
        transaction_index: counter += 1,
        created_at: Time.now,
        updated_at: Time.now,
        contract_address: @contract.address,
      )
      
      @contract.reload
      expect(@contract.current_state).to eq(old_state.stringify_keys)
      
      new_state = { key: 'new_value' }
      
      contract_state = ContractState.create!(
        transaction_hash: @ethscription2.ethscription_id,
        state: new_state,
        type: @contract.current_type,
        init_code_hash: @contract.current_init_code_hash,
        block_number: counter += 1,
        transaction_index: counter += 1,
        created_at: Time.now,
        updated_at: Time.now,
        contract_address: @contract.address,
      )
      
      @contract.reload
      expect(@contract.current_state).to eq(new_state.stringify_keys)

      contract_state.destroy

      @contract.reload
      expect(@contract.current_state).to eq(old_state.stringify_keys)
    end
  end
  
  context 'when a ContractState is created' do
    it 'updates the current_state, current_type, and current_init_code_hash of the Contract' do
      new_state = { key: 'value' }
      new_type = 'NewType'
      new_init_code_hash = SecureRandom.hex(32)
  
      ContractState.create!(
        transaction_hash: @ethscription.ethscription_id,
        state: new_state,
        type: new_type,
        init_code_hash: new_init_code_hash,
        block_number: 1,
        transaction_index: 1,
        created_at: Time.now,
        updated_at: Time.now,
        contract_address: @contract.address,
      )
  
      @contract.reload
      expect(@contract.current_state).to eq(new_state.stringify_keys)
      expect(@contract.current_type).to eq(new_type)
      expect(@contract.current_init_code_hash).to eq(new_init_code_hash)
    end
  end
end
