class ContractCall < ApplicationRecord
  include ContractErrors
  
  enum :call_type, [ :call, :static_call, :create ], prefix: :is
  enum :status, [ :failure, :success ]
  
  attr_accessor :to_contract, :salt, :pending_logs, :to_contract_init_code_hash
  
  belongs_to :created_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'created_contract_address', optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :contract_calls
  
  belongs_to :ethscription, primary_key: 'ethscription_id', foreign_key: 'transaction_hash', optional: true

  def execute!
    self.pending_logs = []
    
    if is_create?
      create_and_validate_new_contract!
    else
      find_and_validate_existing_contract!
    end
    
    result = to_contract.execute_function(
      function,
      args
    )
    
    assign_attributes(
      return_value: result,
      status: :success,
      logs: pending_logs
    )
    
    self.effective_contract_address = to_contract.address
    
    if is_create?
      self.created_contract = to_contract
      to_contract.address
    else
      result
    end
  rescue ContractError, TransactionError => e
    assign_attributes(error: e.message, status: :failure)
    raise
  rescue ReadOnlyFunctionChangedStateError => e
    raise ReadOnlyFunctionChangedStateError, "Invalid change in read-only function: #{function}, #{args.inspect}, to address: #{to_contract.address}. Before: #{to_contract.implementation.initial_state} after: #{to_contract.implementation.state_proxy.serialize}"
  end
  
  def args=(args)
    super(args || {})
  end
  
  def find_and_validate_existing_contract!
    self.to_contract = TransactionContext.get_active_contract(to_contract_address) || Contract.find_by(address: to_contract_address)
    
    if to_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if function&.to_sym == :constructor
      raise ContractError.new("Cannot call constructor function: #{function}", to_contract)
    end
  end
  
  def to_contract_init_code_hash
    @to_contract_init_code_hash ||= TransactionContext.implementation_from_type(to_contract_type)&.init_code_hash
  end
  
  def to_contract_implementation
    TransactionContext.implementation_from_init_code(to_contract_init_code_hash)
  end
  
  def create_and_validate_new_contract!
    if function
      raise ContractError.new("Cannot call function on contract creation")
    end
    
    unless to_contract_implementation.present?
      raise TransactionError.new("Invalid contract: #{to_contract_init_code_hash || to_contract_type}")
    end
    
    if to_contract_implementation.is_abstract_contract
      raise TransactionError.new("Cannot deploy abstract contract: #{to_contract_implementation.name}")
    end
    
    self.to_contract = Contract.new(
      transaction_hash: TransactionContext.transaction_hash,
      address: calculate_new_contract_address,
      current_type: to_contract_implementation.name,
      current_init_code_hash: to_contract_init_code_hash
    )
    
    self.function = :constructor
  end
  
  def calculate_new_contract_address
    if contract_initiated? && salt
      return calculate_new_contract_address_with_salt
    end
    
    rlp_encoded = Eth::Rlp.encode([Integer(from_address, 16), current_nonce])
    
    hash = Digest::Keccak256.hexdigest(rlp_encoded)
    "0x" + hash[24..-1]
  end
  
  def calculate_new_contract_address_with_salt
    address = ContractImplementation.calculate_new_contract_address_with_salt(
      salt, from_address, to_contract_init_code_hash
    )
    
    if Contract.where(address: address).exists?
      raise ContractError.new("Contract already exists at address: #{address}")
    end

    address
  end
  
  def contract_nonce
    in_memory = contract_transaction.contract_calls.count do |call|
      call.from_address == from_address &&
      call.is_create? &&
      call.success?
    end
    
    scope = ContractCall.where(
      from_address: from_address,
      call_type: :create,
      status: :success
    )
    
    in_memory + scope.count
  end
  
  def eoa_nonce
    scope = ContractCall.where(
      from_address: from_address,
      call_type: [:create, :call]
    )
    
    scope.count
  end
  
  def current_nonce
    raise "Not possible" unless is_create?
    
    contract_initiated? ? contract_nonce : eoa_nonce
  end
  
  def contract_initiated?
    internal_transaction_index > 0
  end
  
  def log_event(event)
    pending_logs << event
    nil
  end
end
