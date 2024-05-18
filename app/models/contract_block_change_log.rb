class ContractBlockChangeLog < ApplicationRecord
  belongs_to :contract, foreign_key: :contract_address, primary_key: :address, optional: true
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  
  validates :block_number, presence: true
  validates :contract_address, presence: true
  validates :state_changes, presence: true
  
  def self.save_changes(contract_address, block_number, changes)
    return if changes.empty?
    
    create!(
      contract_address: contract_address,
      block_number: block_number,
      state_changes: changes.to_a
    )
  end

  # TODO: more testing
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
      end
      
      changes_to_apply.each do |change|
        NewContractState.import_records!([change])
      end
      
      NewContractState.delete_state(contract_address: contract_address, keys_to_delete: keys_to_delete)

      logs.delete_all
    end
  end
end
