class TransactionReceipt < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, touch: true

  belongs_to :contract, primary_key: 'address', foreign_key: 'contract_address', touch: true, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash',
  touch: true, optional: true
  has_one :contract, through: :contract_transaction
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }

  enum status: {
    success: 0,
    call_error: 1,
    deploy_error: 2,
    call_to_non_existent_contract: 3,
    system_error: 4,
    json_parse_error: 5,
    error: 6
  }
  
  validate :status_or_errors_check#, :no_contract_on_deploy_error
  
  def contract
    Contract.find_by_address(address)
  end
  
  def address
    effective_contract_address
  end
  
  def no_contract_on_deploy_error
    if (deploy_error? || call_to_non_existent_contract?) && contract_address.present?
      errors.add(:contract_address, "must be blank on deploy error")
    elsif call_error? && contract_address.blank?
      errors.add(:contract_address, "must be present on call error")
    elsif success? && contract_address.blank?
      errors.add(:contract_address, "must be present on success")
    end
  end
  
  def to
    effective_contract_address
  end
  
  def from
    from_address
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
          :return_value
        ],
        methods: [:to, :from]
      )
    ).with_indifferent_access
  end

  private

  def status_or_errors_check
    if !success? && error.blank?
      errors.add(:base, "Status must be success or errors must be non-empty")
    end
  end
end
