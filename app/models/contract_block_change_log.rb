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
