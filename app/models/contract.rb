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
      initial_state: current_state,
      wrapper: wrapper
    )
    
    take_state_snapshot
  end
  
  def self.cache_all_state
    find_each do |contract|
      contract.cache_state
    end
  end
  
  def cache_state(block_number = TransactionReceipt.maximum(:block_number))
    Contract.transaction do
      structure = wrapper.build_structure
      contract = self
      
      # if contract.current_state != structure
        contract.update!(current_state: structure)
      
        state = ContractState.find_or_initialize_by(
          contract_address: address,
          block_number: block_number
        )
        
        state.type ||= contract.current_type
        state.init_code_hash ||= contract.current_init_code_hash
        state.state = structure
        
        state.save!
      # end
    end
  end
  
  def should_take_snapshot?
    state_snapshots.blank? ||
    current_init_code_hash_changed? ||
    current_type_changed?
  end
  
  def take_state_snapshot
    return unless should_take_snapshot?
    
    new_snapshot = ContractStateSnapshot.new(
      type: current_type,
      init_code_hash: current_init_code_hash
    )
    
    state_snapshots.push(new_snapshot)
  end
  
  def load_last_snapshot
    self.current_init_code_hash = state_snapshots.last.init_code_hash
    self.current_type = state_snapshots.last.type
  end
  
  def new_state_for_save(block_number:)
    return if state_snapshots.first == state_snapshots.last
    
    ContractState.new(
      contract_address: address,
      block_number: block_number,
      init_code_hash: state_snapshots.last.init_code_hash,
      type: state_snapshots.last.type,
      state: current_state
    )
  end
  
  def implementation_class
    return unless current_init_code_hash
    
    

    
    # t = current_type == "NameRegistry" ? "NameRegistry01" : current_type
    # ap current_type
    # if current_type == "FacetPortV101"
    #   return RubidityTranspiler.hack_get("FacetPortV101")&.build_class if Rails.env.development?
    # end
    
    BlockContext.supported_contract_class(
      current_init_code_hash, validate: false
    )
  # rescue => e
  #   binding.pry
  end
  
  def wrapper
    @_state_manager ||= StateManager.new(
      self.address,
      implementation_class.state_var_def_json
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
      
      public_functions = implementation.public_abi.keys
      # TODO: This is a bit of a hack
      public_functions << :constructor if new_record?
      
      proxy = UltraMinimalProxy.new(implementation, public_functions.map(&:to_sym))
      function_name = function_name.to_sym
      
      result = if args.is_a?(Hash)
        proxy.__send__(function_name, **args)
      else
        proxy.__send__(function_name, *Array.wrap(args))
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
      wrapper: wrapper
    )
    
    wrapper.state_var_layout = @implementation.class.state_var_def_json
    
    result = yield
    
    @implementation = old_implementation
    
    wrapper.state_var_layout = @implementation.class.state_var_def_json
    
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
      
      if ApiResponseContext.use_v1_api?
        json['current_state']['contract_type'] = current_type
      end
      
      json['abi'] = contract_artifact&.build_class&.abi.as_json
        
      json['source_code'] = [
        {
          language: 'ruby',
          code: contract_artifact&.source_code
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
