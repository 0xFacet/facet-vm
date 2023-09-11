class InternalTransaction < ApplicationRecord
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash
  belongs_to :created_contract, class_name: 'Contract', foreign_key: :created_contract_address,
    primary_key: :address, optional: true 
end