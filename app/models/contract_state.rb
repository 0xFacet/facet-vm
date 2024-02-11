class ContractState < ApplicationRecord
  self.inheritance_column = :_type_disabled
  
  belongs_to :contract, foreign_key: :contract_address, primary_key: :address, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  
  scope :newest_first, lambda {
    order_clause = column_names.include?('transaction_index') ?
    'block_number DESC, transaction_index DESC' : 'block_number DESC'
    order(Arel.sql(order_clause))
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
