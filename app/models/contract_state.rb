class ContractState < ApplicationRecord
  belongs_to :contract, primary_key: 'contract_id', touch: true
  belongs_to :created_by_ethscription, primary_key: 'ethscription_id',
    foreign_key: 'ethscription_id',
    class_name: "Ethscription", touch: true
    
    before_validation :ensure_block_number_and_transaction_index
  
    scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
    
    def as_json(options = {})
      super(
        options.merge(
          only: [
            :eth_transaction_id,
            :contract_id,
            :state,
          ]
        )
      )
    end
    
    private
    
    def ensure_block_number_and_transaction_index
      self.block_number = created_by_ethscription.block_number if block_number.nil?
      self.transaction_index = created_by_ethscription.transaction_index if transaction_index.nil?
    end
end
