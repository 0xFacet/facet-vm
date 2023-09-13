class ContractCall < ApplicationRecord
  include ContractErrors
  
  enum :call_type, [ :call, :static_call, :create ], prefix: :is
  enum :status, [ :failure, :success ]
  
  belongs_to :created_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'created_contract_address', optional: true
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :contract_calls

  def execute!
    result = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      result = validated_to_contract.execute_function(
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
  
  def validated_to_contract
    send(:"validate_#{call_type}!")
    to_contract
  end
  
  def to_contract
    @to_contract ||= if is_create?
      create_and_validate_new_contract!(to_contract_type)
    else
      find_and_validate_existing_contract!(to_contract_address)
    end
  end
  
  def args=(args)
    super(args || {})
  end
  
  def find_and_validate_existing_contract!(address)
    Contract.find_by(address: to_contract_address).tap do |to_contract|
      if to_contract.blank?
        raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
      end
      
      if to_contract_type && !to_contract.implements?(to_contract_type.to_s)
        raise ContractError.new("Contract doesn't implement interface: #{to_contract_address}, #{to_contract_type}", to_contract)
      end
    end
  end
  
  def create_and_validate_new_contract!(to_contract_type)
    unless Contract.type_valid?(to_contract_type)
      raise TransactionError.new("Invalid contract type: #{to_contract_type}")
    end
    
    if Contract.type_abstract?(to_contract_type)
      raise TransactionError.new("Cannot deploy abstract contract: #{to_contract_type}")
    end
    
    Contract.create!(
      transaction_hash: TransactionContext.transaction_hash,
      address: calculate_new_contract_address,
      type: to_contract_type,
    ).tap do |c|
      self.created_contract_address = c.address
    end
  end
  
  def function_object
    public_abi = to_contract.implementation.public_abi
    
    public_abi[function]
  end
  
  def validate_create!
    if function
      raise ContractError.new("Cannot call function on contract creation")
    end
    
    self.function = :constructor
  end
  
  def validate_call!
    if !function_object
      raise ContractError.new("Call to unknown function #{function}", to_contract)
    end
    
    if function.to_sym == :constructor
      raise ContractError.new("Cannot call constructor function: #{function}", to_contract)
    end
  end
  
  def validate_static_call!
    if !function_object
      raise ContractError.new("Call to unknown function #{function}", to_contract)
    end
    
    if !function_object.read_only?
      raise ContractError.new("Cannot call non-read-only function in static call: #{function}", to_contract)
    end
  end

  def calculate_new_contract_address
    # TODO: triple check this works
    rlp_encoded = Eth::Rlp.encode([Integer(from_address, 16), current_nonce])
    
    hash = Digest::Keccak256.new.hexdigest(rlp_encoded)
    
    "0x" + hash[24..-1]
  end
  
  def contract_nonce
    in_memory = contract_transaction.contract_calls.count do |call|
      call.from_address == from_address &&
      call.is_create?
    end
    
    scope = ContractCall.where(
      from_address: from_address,
      call_type: :create
    )
    
    in_memory + scope.count
  end
  
  def eoa_nonce
    scope = ContractCall.where(
      from_address: from_address,
      call_type: [:create, :call],
      internal_transaction_index: 0,
    )
    
    scope.count
  end
  
  def current_nonce
    return unless is_create?
    
    internal_transaction_index.zero? ? eoa_nonce : contract_nonce
  end
  
  def log_event(event)
    logs << event
    nil
  end
end
