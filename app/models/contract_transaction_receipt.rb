class ContractTransactionReceipt < ApplicationRecord
  belongs_to :contract, primary_key: 'address', foreign_key: 'contract_address', touch: true, optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true
  belongs_to :ethscription,
  primary_key: 'ethscription_id', foreign_key: 'transaction_hash',
  touch: true, optional: true
  has_one :contract, through: :contract_transaction

  enum status: {
    success: 0,
    call_error: 1,
    deploy_error: 2,
    call_to_non_existent_contract: 3,
    system_error: 4,
    json_parse_error: 5,
    error: 6
  }
  
  before_validation :clear_logs_if_error#, :ensure_status
  
  validate :status_or_errors_check#, :no_contract_on_deploy_error
  
  def contract
    Contract.find_by_address(address)
  end
  
  def address
    contract_address
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
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :transaction_hash,
          :timestamp,
          :contract_address,
          :caller,
          :status,
          :function_name,
          :function_args,
          :error_message,
          :logs
        ]
      )
    ).tap do |json|
      [:block_blockhash, :block_number, :transaction_index].each do |key|
        json[key] = contract_transaction&.public_send(key)
      end
    end.with_indifferent_access
  end

  private

  def status_or_errors_check
    if !success? && error_message.blank?
      errors.add(:base, "Status must be success or errors must be non-empty")
    end
  end
  
  def clear_logs_if_error
    self.logs = [] if !success?
  end
end
