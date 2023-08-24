class ContractCallReceipt < ApplicationRecord
  belongs_to :contract, primary_key: 'contract_id', touch: true, optional: true
    
  belongs_to :created_by_ethscription,
    primary_key: 'ethscription_id', foreign_key: 'ethscription_id',
    class_name: "Ethscription", touch: true
    
  enum status: {
    success: 0,
    call_error: 1,
    deploy_error: 2,
    system_error: 3
  }
  
  before_validation :clear_logs_if_error#, :ensure_status
  
  validate :status_or_errors_check, :no_contract_on_deploy_error
  
  def no_contract_on_deploy_error
    if deploy_error? && contract_id.present?
      errors.add(:contract_id, "must be blank on deploy error")
    elsif call_error? && contract_id.blank?
      errors.add(:contract_id, "must be present on call error")
    end
  end
  
  def failed_deployment_contract_id
    eth_transaction_id if deploy_error?
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :timestamp,
          :contract_id,
          :caller,
          :status,
          :function_name,
          :function_args,
          :error_message,
          :logs
        ],
        methods: [
          :failed_deployment_contract_id
        ]
      )
    ).tap do |json|
      json['ethscription_id'] = eth_transaction_id
    end
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
