class ContractBlockChangeLog < ApplicationRecord
  belongs_to :contract, foreign_key: :contract_address, primary_key: :address, optional: true
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  
  def self.save_changes(contract_address, block_number, changes)
    state_changes = changes[:state].select { |_, change| change[:from] != change[:to] }
    
    if changes[:implementation] && (changes[:implementation][:from] != changes[:implementation][:to])
      implementation_change = changes[:implementation]
    end
    
    implementation_change ||= {}
    
    return if state_changes.blank? && implementation_change.blank?
      
    create!(
      contract_address: contract_address,
      block_number: block_number,
      state_changes: state_changes.to_a,
      implementation_change: implementation_change
    )
  end
  
  def self.historical_state(contract_address, target_block)
    current_state = nil
    current_block = nil
  
    ActiveRecord::Base.transaction do
      # Lock the current state rows and fetch them
      current_state = NewContractState.lock.where(contract_address: contract_address)
      
      # Lock the EthBlock table and fetch the current block number
      current_block = EthBlock.max_processed_block_number
    end
  
    state = current_state.each_with_object({}) do |record, hash|
      hash[record.key] = record.value
    end
  
    # Fetch the change logs from the current block back to the target block
    change_logs = where(contract_address: contract_address)
      .where('block_number > ? AND block_number <= ?', target_block, current_block)
      .order(block_number: :desc)
  
    # Apply changes in reverse order
    change_logs.each do |log|
      log.state_changes.each do |change_key, change|
        if state[change_key] == change['to']
          state[change_key] = change['from']
        else
          raise "Historical value mismatch for #{change_key}: #{state[change_key]} != #{change['to']}"
        end
      end
    end
  
    state
  end
  
  def self.historical_value(contract_address, key, target_block)
    key = Array.wrap(key)
    current_state = nil
    current_block = nil
  
    ActiveRecord::Base.transaction do
      current_state = NewContractState.where(contract_address: contract_address).
        where("key = ?", key.to_json).first
      
      current_block = EthBlock.max_processed_block_number
    end
    
    current_value = current_state ? current_state.value : 0
  
    if current_block - target_block > 20
      raise "Historical value query range too large: #{current_block - target_block} blocks"
    end
    
    # Fetch the change logs from the current block back to the target block
    change_logs = where(contract_address: contract_address)
      .where('block_number > ? AND block_number <= ?', target_block, current_block)
      .order(block_number: :desc)
    
    # Apply changes in reverse order
    change_logs.each do |log|
      log.state_changes.each do |change_key, change|
        next unless change_key == key
  
        if change['to'] == current_value
          current_value = change['from']
        else
          raise "Historical value mismatch for key '#{key}' at block #{log.block_number}: expected '#{change['to']}', got '#{current_value}'"
        end
      end
    end
  
    current_value
  end
  
  def self.rollback_all_changes(to_block = nil)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(<<-SQL)
        LOCK TABLE
        contract_block_change_logs, new_contract_states, contracts, eth_blocks
        IN EXCLUSIVE MODE NOWAIT
      SQL
      
      yield if block_given?
      
      logs = ContractBlockChangeLog.
              where('block_number > ?', to_block).
              order(block_number: :desc)

      changes_to_apply = []
      keys_to_delete = []

      logs.each do |log|
        log.state_changes.each do |change|
          keys, value = change
          
          old_value = value['from']
          if old_value.nil?
            keys_to_delete << keys
          else
            changes_to_apply << {
              contract_address: log.contract_address,
              key: keys,
              value: old_value
            }
          end
        end
        
        if log.implementation_change&.dig('from')&.present?
          Contract.where(address: log.contract_address).update_all(
            current_init_code_hash: log.implementation_change['from']['init_code_hash'],
            current_type: log.implementation_change['from']['type']
          )
        end
        
        NewContractState.delete_state(contract_address: log.contract_address, keys_to_delete: keys_to_delete)
      end

      changes_to_apply.each do |change|
        NewContractState.import_records!([change])
      end

      Contract.where(address: logs.map(&:contract_address).uniq).update_all("lock_version = lock_version + 1")
      
      logs.delete_all
      EthBlock.where("block_number > ?", to_block).delete_all
    end
  end
  
  def self.rollback_changes(contract_address, block_number)
    ContractBlockChangeLog.transaction do
      logs = where(contract_address: contract_address)
            .where('block_number > ?', block_number)
            .order(block_number: :desc)

      changes_to_apply = []
      keys_to_delete = []

      logs.each do |log|
        log.state_changes.each do |change|
          keys, value = change
          
          old_value = value['from']
          if old_value.nil?
            keys_to_delete << keys
          else
            changes_to_apply << { contract_address: contract_address, key: keys,
              value: old_value }
          end
        end
        
        if log.implementation_change&.dig('from')&.present?
          Contract.find_by_address(contract_address).update!(
            current_init_code_hash: log.implementation_change['from']['init_code_hash'],
            current_type: log.implementation_change['from']['type']
          )
        end
      end
      
      changes_to_apply.each do |change|
        NewContractState.import_records!([change])
      end
      
      NewContractState.delete_state(contract_address: contract_address, keys_to_delete: keys_to_delete)
      
      logs.delete_all
    end
  end
end
