class ContractCall < ApplicationRecord
  include ContractErrors
  
  enum :call_type, [ :call, :static_call, :create ], prefix: :is
  enum :status, [ :failure, :success ]
  
  belongs_to :created_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'created_contract_address', optional: true

  def execute!
    result = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      result = target_contract.execute_function(
        function, args
      )
      
      if function_object.read_only? || is_static_call?
        raise ActiveRecord::Rollback
      end
    end
    
    assign_attributes(return_value: result, status: :success)
    result
  rescue ContractError, TransactionError => e
    assign_attributes(error: e.message, status: :failure)
    raise
  end
  
  def target_contract
    validate_to_contract!
    validate_function!
    
    self.function = :constructor if is_create?
    
    to_contract
  end
  
  def to_contract
    @to_contract ||= if is_create?
      create_contract!
    else
      Contract.find_by(address: to_contract_address)
    end
  end
  
  def create_contract!
    validate_contract_creation!
    
    Contract.create!(
      transaction_hash: TransactionContext.transaction_hash,
      address: calculate_msg_sender_contract_address,
      type: to_contract_type,
    ).tap do |c|
      self.created_contract_address = c.address
    end
  end
  
  def validate_to_contract!
    if to_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if to_contract_type && !to_contract.implements?(to_contract_type.to_s)
      raise ContractError.new("Contract doesn't implement interface: #{to_contract_address}, #{to_contract_type}", to_contract)
    end
  end
  
  def function_object
    public_abi = to_contract.implementation.public_abi
    
    public_abi[function]
  end
  
  def validate_function!
    function = function_object

    if !function && !is_create?
      raise ContractError.new("Call to unknown function #{function}", to_contract)
    end
    
    if is_static_call? && !function.read_only?
      raise ContractError.new("Cannot call non-read-only function in static call: #{function}", to_contract)
    end
    
    if !is_create? && function.constructor?
      raise ContractError.new("Cannot call constructor function: #{function}", to_contract)
    end
    
    if is_create? && function.present?
      raise ContractError.new("Cannot call function on contract creation", to_contract)
    end
  end
  
  def calculate_msg_sender_contract_address
    deployer = TransactionContext.msg_sender.serialize
    
    scope = ContractCall.where(
      from_address: TransactionContext.msg_sender.serialize,
      call_type: :create,
      internal_transaction_index: 0,
    ).where.not(transaction_hash: TransactionContext.transaction_hash)
    
    nonce = scope.count
    
    rlp_encoded = Eth::Rlp.encode([Integer(deployer, 16), nonce])
  
    hash = Digest::Keccak256.new.hexdigest(rlp_encoded)
  
    "0x" + hash[24..-1]
  end
  
  def validate_contract_creation!
    unless Contract.valid_contract_types.include?(to_contract_type.to_sym)
      raise TransactionError.new("Invalid contract type: #{to_contract_type}")
    end
    
    implementation_class = "Contracts::#{to_contract_type}".constantize
    
    if implementation_class.is_abstract_contract
      raise TransactionError.new("Cannot deploy abstract contract: #{to_contract_type}")
    end
  end
  
  def log_event(event)
    logs << event
    event
  end
end
