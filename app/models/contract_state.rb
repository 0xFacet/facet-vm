class ContractState < ApplicationRecord
  belongs_to :contract, foreign_key: :contract_address, primary_key: :address, touch: true, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  belongs_to :ethscription,
  primary_key: 'ethscription_id', foreign_key: 'transaction_hash',
  touch: true
  
  scope :newest_first, -> {
    order(block_number: :desc, transaction_index: :desc, internal_transaction_index: :desc) 
  }
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :transaction_hash,
          :contract_address,
          :state,
        ]
      )
    )
  end
end
