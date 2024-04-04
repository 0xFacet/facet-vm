class Contract < ApplicationRecord
  include FacetRailsCommon::OrderQuery
  include ContractErrors
  
  initialize_order_query({
    newest_first: [
      [:block_number, :desc],
      [:transaction_index, :desc],
      [:created_at, :desc, unique: true]
    ],
    oldest_first: [
      [:block_number, :asc],
      [:transaction_index, :asc],
      [:created_at, :asc, unique: true]
    ]
  }, page_key_attributes: [:address])
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  belongs_to :contract_artifact, foreign_key: :current_init_code_hash, primary_key: :init_code_hash, optional: true
  
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
  
  def should_take_snapshot?
    state_snapshots.blank? ||
    current_init_code_hash_changed? ||
    current_type_changed? ||
    implementation.state_proxy.state_changed
  end
  
  def take_state_snapshot
    return unless should_take_snapshot?
    
    new_snapshot = ContractStateSnapshot.new(
      state: implementation.state_proxy.serialize,
      type: current_type,
      init_code_hash: current_init_code_hash
    )
    
    state_snapshots.push(new_snapshot)
  end
  
  def load_last_snapshot
    self.current_init_code_hash = state_snapshots.last.init_code_hash
    self.current_type = state_snapshots.last.type
    
    implementation.state_proxy.load(state_snapshots.last.state.deep_dup)
  end
  
  def new_state_for_save(block_number:)
    return if state_snapshots.first == state_snapshots.last
    
    ContractState.new(
      contract_address: address,
      block_number: block_number,
      init_code_hash: state_snapshots.last.init_code_hash,
      type: state_snapshots.last.type,
      state: state_snapshots.last.state
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
    
    implementation.state_proxy.load(post_execution_state)
    
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
      if association(:transaction_receipt).loaded?
        json['deployment_transaction'] = transaction_receipt
      end
      
      json['current_state'] = if options[:include_current_state]
        current_state
      else
        {}
      end
      
      json['current_state']['contract_type'] = current_type
      
      if association(:contract_artifact).loaded?
        json['abi'] = contract_artifact&.build_class&.abi.as_json
        
        json['source_code'] = [
          {
            language: 'ruby',
            code: contract_artifact&.source_code
          }
        ]
      end
    end
  end
  
  def static_call(name, args = {})
    ContractTransaction.make_static_call(
      contract: address, 
      function_name: name, 
      function_args: args
    )
  end
  
  def self.get_storage_value_by_path(contract_address, keys)
    sanitized_keys = keys.map do |key|
      ActiveRecord::Base.connection.quote_string(key.to_s)
    end
  
    # Convert sanitized keys to a JSON path format expected by PostgreSQL
    json_path = "{#{sanitized_keys.join(',')}}"
  
    # Construct a SQL expression that checks the type of the JSON value
    # and returns the value only if it's not an 'object' or 'array'.
    sql_expression = <<-SQL
      CASE 
        WHEN jsonb_typeof(current_state #> '#{json_path}') IN ('object', 'array') THEN NULL
        ELSE current_state #>> '#{json_path}'
      END
    SQL
  
    # Use `pick` with the safely constructed SQL expression
    result = where(address: contract_address).pick(Arel.sql(sql_expression))
  end
end
