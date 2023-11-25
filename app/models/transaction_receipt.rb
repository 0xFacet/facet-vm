class TransactionReceipt < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, touch: true

  belongs_to :contract, primary_key: 'address', foreign_key: 'effective_contract_address', touch: true, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash',
  touch: true, optional: true
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
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
