class ContractState < ApplicationRecord
  self.inheritance_column = :_type_disabled
  
  belongs_to :contract, foreign_key: :contract_address, primary_key: :address, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash',
  optional: true
  
  scope :newest_first, -> {
    order(block_number: :desc, transaction_index: :desc, contract_address: :desc)
  }
  
  scope :oldest_first, -> {
    order(block_number: :asc, transaction_index: :asc, contract_address: :asc)
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
