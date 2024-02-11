class Contract < ApplicationRecord
  class StateSnapshot
    attr_accessor :state, :type, :init_code_hash
    
    def initialize(state:, type:, init_code_hash:)
      @state = state
      @type = type
      @init_code_hash = init_code_hash
    end
    
    def ==(other)
      self.class == other.class &&
      state.serialize(dup: false) == other.state.serialize(dup: false) &&
      type == other.type &&
      init_code_hash == other.init_code_hash
    end
    
    def serialize(dup: true)
      {
        state: state.serialize(dup: dup),
        type: type,
        init_code_hash: init_code_hash
      }
    end
  end
  
  include ContractErrors
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  # belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  has_many :contract_calls, foreign_key: :effective_contract_address, primary_key: :address
  has_one :transaction_receipt, through: :contract_transaction
  delegate :implements?, to: :implementation

  attr_reader :implementation
  
  attr_accessor :state_snapshots
  def state_snapshots
    @state_snapshots ||= []
  end
  
  def initialize_state
    @implementation = implementation_class.new(
      initial_state: current_state
    )
    
    take_state_snapshot
  end
  
  def take_state_snapshot
    last_snapshot = state_snapshots.last
    
    new_snapshot = StateSnapshot.new(
      state: implementation.state_proxy,
      type: current_type,
      init_code_hash: current_init_code_hash
    )
    
    if new_snapshot != last_snapshot
      state_snapshots.push(new_snapshot)
    end
  end
  
  def load_last_snapshot
    self.current_init_code_hash = state_snapshots.last.init_code_hash
    self.current_type = state_snapshots.last.type
    
    @implementation = implementation_class.new(
      initial_state: state_snapshots.last.state.serialize
    )
  end
  
  def new_state_for_save(block_number:)
    return if state_snapshots.first == state_snapshots.last
    
    ContractState.new(
      contract_address: address,
      block_number: block_number,
      **state_snapshots.last.serialize(dup: false)
    )
  end
  
  
  def implementation_class
    return unless current_init_code_hash
    
    BlockContext.supported_contract_class(
      current_init_code_hash, validate: false
    )
  end
  
  def self.types_that_implement(base_type)
    ContractArtifact.types_that_implement(base_type)
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
      
      result
    end
  end
  
  def with_correct_implementation
    old_hash = implementation.send(:class).init_code_hash
    new_hash = implementation_class.init_code_hash
    in_upgrade = old_hash != new_hash
    
    unless in_upgrade
      return yield
    end
    
    old_implementation = implementation
    @implementation = implementation_class.new(
      initial_state: old_implementation.state_proxy.serialize
    )
    
    result = yield
    
    post_execution_state = implementation.state_proxy.serialize
    
    @implementation = old_implementation
    
    old_implementation.state_proxy.load(post_execution_state)
    
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
