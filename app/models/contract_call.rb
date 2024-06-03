class ContractCall < ApplicationRecord
  include FacetRailsCommon::OrderQuery
  include ContractErrors
  
  initialize_order_query({
    newest_first: [
      [:block_number, :desc],
      [:transaction_index, :desc],
      [:internal_transaction_index, :desc, unique: true]
    ],
    oldest_first: [
      [:block_number, :asc],
      [:transaction_index, :asc],
      [:internal_transaction_index, :asc, unique: true]
    ]
  }, page_key_attributes: [:block_number, :transaction_index, :internal_transaction_index])
  
  before_validation :ensure_runtime_ms
  
  attr_accessor :to_contract, :salt, :pending_logs, :to_contract_init_code_hash, :to_contract_source_code,
    :in_low_level_call_context, :call_stack, :internal_call_read_only_context_stack
  
  belongs_to :created_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'created_contract_address', optional: true
  belongs_to :called_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'to_contract_address', optional: true
  belongs_to :effective_contract, class_name: 'Contract', primary_key: 'address', foreign_key: 'effective_contract_address', optional: true
  
  belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  belongs_to :contract_transaction, foreign_key: :transaction_hash,
    primary_key: :transaction_hash, optional: true, inverse_of: :contract_calls, autosave: false

  def implementation_class
    init_code_hash = state_manager.get_implementation[:init_code_hash]
    implementation_class = BlockContext.supported_contract_class(
      init_code_hash,
      validate: false
    )
  end
  
  def internal_call_read_only_context_stack
    @internal_calls ||= []
  end
  
  def state_manager
    effective_contract.state_manager
  end
  
  def implementation
    TransactionContext.log_call("ContractCall", "GetImplementation") do
      @_implementation ||= implementation_class.new(
        state_manager: state_manager
      )
    end
  end
  
  def in_read_only_context?
    @call_stack.in_read_only_context?(self)
  end
  
  def internal_call_in_read_only_context?
    internal_call_read_only_context_stack.any?{|i| i == true}
  end
  
  def read_only?
    implementation.public_abi[function].read_only?
  end
  
  def call_function(function, args)
    if args.is_a?(Hash)
      implementation.handle_call_from_proxy(function, **args)
    else
      implementation.handle_call_from_proxy(function, *Array.wrap(args))
    end
  end
  
  def execute!
    self.pending_logs = []
    
    if is_create?
      create_and_validate_new_contract!
    else
      find_and_validate_existing_contract!
    end
    
    if !implementation.public_abi.key?(function)
      raise ContractError.new("Call to unknown function: #{function}", self)
    end
    
    if is_create?
      if function.to_sym != :constructor
        raise ContractError.new("Cannot call function on contract creation: #{function}", self)
      end
      
      if in_read_only_context?
        raise ContractError,
        "Invalid change in read-only context: #{function}, #{args.inspect}. Contract: #{effective_contract.address}."
      end
    else
      if is_static_call? && !in_read_only_context?
        raise ContractError.new("Cannot call non-read-only function in static call: #{function}", self)
      end
    end
    
    internal_call_read_only_context_stack.push(in_read_only_context?)
    
    result = nil
    
    state_manager.with_state_var_layout(implementation_class.state_var_def_json) do
      result = call_function(function, args)
    end
    
    assign_attributes(
      return_value: result,
      status: :success,
      logs: pending_logs,
      end_time: Time.current
    )
    
    assign_contract
    
    is_create? ? created_contract.address : result
  rescue InvalidStateVariableChange
    raise ContractError,
    "Invalid change in read-only context: #{function}, #{args.inspect}. Contract: #{effective_contract.address}."
  rescue ContractError, TransactionError => e
    assign_attributes(error_message: e.message, status: :failure, end_time: Time.current)
    
    assign_contract
    
    raise
  end
  
  def assign_contract
    return unless effective_contract
    
    if is_create?
      self.created_contract = effective_contract.tap do |c|
        c.assign_attributes(
          deployed_successfully: success?
        )
        
        if failure?
          c.assign_attributes(
            current_init_code_hash: nil,
            current_type: nil,
            current_state: {}
          )
        end
      end
    elsif is_call?
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
    self.effective_contract = TransactionContext.get_existing_contract(to_contract_address)
    
    if effective_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if function&.to_sym == :constructor
      raise ContractError.new("Cannot call constructor function: #{function}", effective_contract)
    end
  end
  
  def create_and_validate_new_contract!
    TransactionContext.log_call("ContractCreation", "TransactionContext.create_new_contract") do
      self.effective_contract = TransactionContext.create_new_contract(
        address: calculate_new_contract_address,
        init_code_hash: to_contract_init_code_hash,
        source_code: to_contract_source_code
      )
    end
    
    if implementation_class.is_abstract_contract
      raise TransactionError.new("Cannot deploy abstract contract: #{implementation_class.name}")
    end
    
    if function
      raise ContractError.new("Cannot call function on contract creation")
    end
    
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
  
  def current_nonce
    raise "Not possible" unless is_create?
    
    if contract_initiated?
      BlockContext.calculate_contract_nonce(from_address)
    else
      BlockContext.calculate_eoa_nonce(from_address)
    end
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
end
