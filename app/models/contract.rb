class Contract < ApplicationRecord
  include ContractErrors
    
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  has_many :contract_calls, foreign_key: :effective_contract_address, primary_key: :address
  has_one :transaction_receipt, through: :contract_transaction

  attr_reader :implementation
  
  delegate :implements?, to: :implementation
  
  after_initialize :set_normalized_initial_state
  
  def set_normalized_initial_state
    @normalized_initial_state = JsonSorter.sort_hash(current_state)
  end
  
  def normalized_state_changed?
    @normalized_initial_state != JsonSorter.sort_hash(current_state)
  end
  
  def implementation_class
    return unless current_init_code_hash
    
    TransactionContext.supported_contract_class(
      current_init_code_hash, validate: false
    )
  end
  
  def self.types_that_implement(base_type)
    ContractArtifact.types_that_implement(base_type)
  end
  
  def should_save_new_state?
    current_init_code_hash_changed? ||
    current_type_changed? ||
    normalized_state_changed?
  end
  
  def save_new_state_if_needed!(transaction:)
    return unless should_save_new_state?
    
    states.create!(
      transaction_hash: transaction.transaction_hash,
      block_number: transaction.block_number,
      transaction_index: transaction.transaction_index,
      state: current_state,
      type: current_type,
      init_code_hash: current_init_code_hash
    )
  end
  
  def execute_function(function_name, args, is_static_call:)
    with_correct_implementation do
      if !implementation.public_abi[function_name]
        raise ContractError.new("Call to unknown function: #{function_name}", self)
      end
      
      read_only = implementation.public_abi[function_name].read_only?
      
      if is_static_call && !read_only
        raise ContractError.new("Cannot call non-read-only function in static call: #{function_name}", self)
      end
      
      result = if args.is_a?(Hash)
        implementation.public_send(function_name, **args)
      else
        implementation.public_send(function_name, *Array.wrap(args))
      end
      
      unless read_only
        self.current_state = self.current_state.merge(implementation.state_proxy.serialize)
      end
      
      result
    end
  end
  
  def with_correct_implementation
    old_implementation = implementation
    @implementation = implementation_class.new(
      initial_state: old_implementation&.state_proxy&.serialize ||
        current_state
    )
    
    result = yield
    
    post_execution_state = implementation.state_proxy.serialize
    
    if old_implementation
      @implementation = old_implementation
      implementation.state_proxy.load(post_execution_state)
    end
    
    result
  end
  
  def fresh_implementation_with_current_state
    implementation_class.new(initial_state: current_state)
  end
  
  def self.deployable_contracts
    ContractArtifact.deployable_contracts
  end
  
  def self.all_abis(...)
    ContractArtifact.all_abis(...)
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :address,
          :transaction_hash,
          :current_init_code_hash,
          :current_type
        ]
      )
    ).tap do |json|
      if implementation_class
        json['abi'] = implementation_class.abi.as_json
      end
      
      if association(:transaction_receipt).loaded?
        json['deployment_transaction'] = transaction_receipt
      end
      
      json['current_state'] = if options[:include_current_state]
        current_state
      else
        {}
      end
      
      json['current_state']['contract_type'] = current_type
      
      json['source_code'] = [
        {
          language: 'ruby',
          code: implementation_class&.source_code
        }
      ]
    end
  end
  
  def static_call(name, args = {})
    ContractTransaction.make_static_call(
      contract: address, 
      function_name: name, 
      function_args: args
    )
  end
end
