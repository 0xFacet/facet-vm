class TransactionReceipt < ApplicationRecord
  include OrderQuery
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, inverse_of: :transaction_receipts, optional: true, autosave: false

  belongs_to :contract, primary_key: 'address', foreign_key: 'effective_contract_address', optional: true, autosave: false
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :transaction_receipt, autosave: false
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash',
  optional: true, autosave: false, inverse_of: :transaction_receipt
  
  order_query :newest_first,
    [:block_number, :desc],
    [:transaction_index, :desc, unique: true]
  
  order_query :oldest_first,
    [:block_number, :asc],
    [:transaction_index, :asc, unique: true]
  
  def self.find_by_page_key(...)
    find_by_transaction_hash(...)
  end
  
  def page_key
    transaction_hash
  end
    
  def contract
    Contract.find_by_address(address)
  end
  
  def address
    effective_contract_address
  end
  
  def to
    to_contract_address
  end
  
  def from
    from_address
  end
  
  def contract_address
    created_contract_address
  end

  def to_or_contract_address
    to || contract_address
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :transaction_hash,
          :call_type,
          :runtime_ms,
          :block_timestamp,
          :status,
          :function,
          :args,
          :error,
          :logs,
          :block_blockhash,
          :block_number,
          :transaction_index,
          :gas_price,
          :gas_used,
          :transaction_fee,
          :return_value,
          :effective_contract_address
        ],
        methods: [:to, :from, :contract_address, :to_or_contract_address]
      )
    ).with_indifferent_access
  end
  
  def failure?
    status.to_s == 'failure'
  end
  
  def success?
    status.to_s == 'success'
  end
end
