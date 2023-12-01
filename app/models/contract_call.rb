class ContractCall < ApplicationRecord
  include ContractErrors
  
  before_validation :ensure_runtime_ms, :trim_failed_contract_deploys
  
  attr_accessor :to_contract, :salt, :pending_logs, :to_contract_init_code_hash, :to_contract_source_code
  
  belongs_to :created_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'created_contract_address', optional: true
  belongs_to :called_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'to_contract_address', optional: true
  belongs_to :effective_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'effective_contract_address', optional: true
  
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :contract_calls
  
  belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  scope :newest_first, -> { order(
    block_number: :desc,
    transaction_index: :desc,
    internal_transaction_index: :desc
  ) }

  def execute!
    self.pending_logs = []
    
    if is_create?
      create_and_validate_new_contract!
    else
      find_and_validate_existing_contract!
    end
    
    result = effective_contract.execute_function(
      function,
      args,
      is_static_call: is_static_call?
    )
    
    assign_attributes(
      return_value: result,
      status: :success,
      logs: pending_logs,
      end_time: Time.current
    )
    
    assign_contract
    
    is_create? ? created_contract.address : result
  rescue ContractError, TransactionError => e
    assign_attributes(error_message: e.message, status: :failure, end_time: Time.current)
    
    assign_contract
    
    raise
  end
  
  def assign_contract
    if is_create?
      self.created_contract = effective_contract.tap do |c|
        c.assign_attributes(
          deployed_successfully: success?
        )
      end
    elsif is_call? && effective_contract
      self.called_contract = effective_contract
    end
  end
  
  def error_message=(msg)
    self.error = {
      message: msg.strip
    }
  end
  
  def args=(args)
    super(args.nil? ? {} : args)
  end
  
  def find_and_validate_existing_contract!
    self.effective_contract = TransactionContext.get_active_contract(to_contract_address) ||
      Contract.find_by(deployed_successfully: true, address: to_contract_address)
    
    if effective_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if function&.to_sym == :constructor
      raise ContractError.new("Cannot call constructor function: #{function}", effective_contract)
    end
  end
  
  def create_and_validate_new_contract!
    self.effective_contract = Contract.new(
      transaction_hash: TransactionContext.transaction_hash.value,
      block_number: TransactionContext.block.number.value,
      transaction_index: TransactionContext.transaction_index,
      address: calculate_new_contract_address
    )
    
    to_contract_implementation = TransactionContext.supported_contract_class(
      to_contract_init_code_hash,
      to_contract_source_code
    )
    
    if function
      raise ContractError.new("Cannot call function on contract creation")
    end
    
    if to_contract_implementation.is_abstract_contract
      raise TransactionError.new("Cannot deploy abstract contract: #{to_contract_implementation.name}")
    end
    
    self.effective_contract.assign_attributes(
      current_type: to_contract_implementation.name,
      current_init_code_hash: to_contract_init_code_hash
    )
    
    self.function = :constructor
  rescue UnknownInitCodeHash => e
    raise TransactionError.new("Invalid contract: #{to_contract_init_code_hash}")
  rescue ContractDefinitionError => e
    raise TransactionError.new("Invalid contract: #{e.message}")
  end
  
  def calculate_new_contract_address
    if contract_initiated? && salt
      return calculate_new_contract_address_with_salt
    end
    
    rlp_encoded = Eth::Rlp.encode([
      Integer(from_address, 16),
      current_nonce,
      "facet"
    ])
    
    hash = Digest::Keccak256.hexdigest(rlp_encoded)
    "0x" + hash.last(40)
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
          :block_blockhash,
          :block_timestamp,
          :block_number,
          :transaction_index,
          :internal_transaction_index,
          :function,
          :args,
          :call_type,
          :return_value,
          :logs,
          :error,
          :status,
          :runtime_ms,
          :effective_contract_address
        ],
        methods: [:to, :from, :contract_address, :to_or_contract_address]
      )
    )
  end
  
  def calculated_runtime_ms
    (end_time - start_time) * 1000
  end
  
  def is_static_call?
    call_type.to_s == "static_call"
  end
  
  def is_create?
    call_type.to_s == "create"
  end
  
  def is_call?
    call_type.to_s == "call"
  end
  
  def failure?
    status.to_s == 'failure'
  end
  
  def success?
    status.to_s == 'success'
  end
  
  private
  
  def ensure_runtime_ms
    return if runtime_ms
    
    self.runtime_ms = calculated_runtime_ms
  end
  
  def trim_failed_contract_deploys
    if failure? && created_contract
      created_contract.assign_attributes(
        current_init_code_hash: nil,
        current_type: nil,
        current_state: {}
      )
    end
  end
end
