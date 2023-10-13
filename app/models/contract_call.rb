class ContractCall < ApplicationRecord
  include ContractErrors
  
  enum :call_type, [ :call, :static_call, :create ], prefix: :is
  enum :status, [ :failure, :success ]
  
  attr_accessor :to_contract, :salt, :pending_logs
  
  belongs_to :created_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'created_contract_address', optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :contract_calls
  
  belongs_to :ethscription, primary_key: 'ethscription_id', foreign_key: 'transaction_hash', optional: true

  before_validation :set_effective_contract_address

  def execute!
    result = nil
    self.pending_logs = []
    
    ActiveRecord::Base.transaction(requires_new: true) do
      if is_create?
        create_and_validate_new_contract!(to_contract_type)
      else
        find_and_validate_existing_contract!(to_contract_address)
      end
      
      result, state_changed = to_contract.execute_function(
        function,
        args
      ).values_at(:result, :state_changed)
      
      if function_object.read_only? && state_changed
        raise ReadOnlyFunctionChangedStateError, "Invalid change in read-only function: #{function}, #{args.inspect}, to address: #{to_contract.address}"
      end
    end
    
    assign_attributes(
      return_value: result,
      status: :success,
      logs: pending_logs
    )
    
    self.created_contract = to_contract if is_create?
    
    result
  rescue ContractError, TransactionError => e
    assign_attributes(error: e.message, status: :failure)
    raise
  end
  
  def args=(args)
    super(args || {})
  end
  
  def find_and_validate_existing_contract!(address)
    self.to_contract = Contract.find_by(address: to_contract_address)
    
    if to_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if to_contract_type && !to_contract.implements?(to_contract_type.to_s)
      raise ContractError.new("Contract doesn't implement interface: #{to_contract_address}, #{to_contract_type}", to_contract)
    end
      
    if !function_object
      raise ContractError.new("Call to unknown function #{function}", to_contract)
    end
    
    if function.to_sym == :constructor
      raise ContractError.new("Cannot call constructor function: #{function}", to_contract)
    end
    
    if is_static_call? && !function_object.read_only?
      raise ContractError.new("Cannot call non-read-only function in static call: #{function}", to_contract)
    end
  end
  
  def create_and_validate_new_contract!(to_contract_type)
    if function
      raise ContractError.new("Cannot call function on contract creation")
    end
    
    unless Contract.type_valid?(to_contract_type)
      raise TransactionError.new("Invalid contract type: #{to_contract_type}")
    end
    
    if Contract.type_abstract?(to_contract_type)
      raise TransactionError.new("Cannot deploy abstract contract: #{to_contract_type}")
    end
    
    self.to_contract = Contract.create!(
      transaction_hash: TransactionContext.transaction_hash,
      address: calculate_new_contract_address,
      type: to_contract_type,
    )
    
    self.function = :constructor
  end
  
  def function_object
    public_abi = to_contract.implementation.public_abi
    
    public_abi[function]
  end
  
  def calculate_new_contract_address
    if contract_initiated? && salt
      return calculate_new_contract_address_with_salt
    end
    
    rlp_encoded = Eth::Rlp.encode([Integer(from_address, 16), current_nonce])
    
    hash = Digest::Keccak256.new.hexdigest(rlp_encoded)
    
    "0x" + hash[24..-1]
  end
  
  def calculate_new_contract_address_with_salt
    address = ContractImplementation.calculate_new_contract_address_with_salt(
      salt, from_address, to_contract_type
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
  
  private
  
  def set_effective_contract_address
    self.effective_contract_address = if is_create?
      created_contract_address
    else
      to_contract_address
    end
  end
end
