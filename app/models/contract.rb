class Contract < ApplicationRecord
  class StaticCallError < StandardError; end
  
  class ContractError < StandardError
    attr_accessor :contract
    attr_accessor :error_status
  
    def initialize(message, contract)
      super(message)
      @contract = contract
    end
  end
  
  class TransactionError < StandardError; end
  class ContractRuntimeError < ContractError; end
  class ContractDefinitionError < ContractError; end
  class StateVariableTypeError < StandardError; end
  class VariableTypeError < StandardError; end
  class StateVariableMutabilityError < StandardError; end
  class ArgumentError < StandardError; end
  
  class ContractProxy
    attr_accessor :contract, :operation
  
    def initialize(contract, operation:)
      @contract = contract
      @operation = operation
      define_contract_methods
    end
    
    def method_missing(name, *args, &block)
      raise ContractError.new("Call to unknown function #{name}", contract)
    end
  
    private
    
    def abi
      contract.abi
    end
  
    def define_contract_methods
      filtered_abi = contract.public_abi.select do |name, func|
        case operation
        when :static_call
          func.read_only?
        when :call
          !func.constructor?
        when :deploy
          true
        end
      end
      
      filtered_abi.each do |name, _|
        define_singleton_method(name) do |args|
          contract.execute_function(name, args)
        end
      end
    end
  end
  
  # has_paper_trail on: [:create, :update]

  # belongs_to :eth_transaction, foreign_key: 'contract_id', primary_key: 'transaction_hash'
  # has_one :creation_ethscription, through: :eth_transaction, class_name: "Ethscription",
  #   inverse_of: :created_contract, source: :ethscription
  # has_many :call_receipts, foreign_key: 'contract_id', primary_key: 'contract_id',
  #   class_name: "ContractCallReceipt", autosave: true, dependent: :destroy
  # has_many :states, foreign_key: 'contract_id', primary_key: 'contract_id',
  #   class_name: "ContractState", autosave: true, dependent: :destroy
    
  has_many :call_receipts, primary_key: 'contract_id', class_name: "ContractCallReceipt", dependent: :destroy
  has_many :states, primary_key: 'contract_id', class_name: "ContractState", dependent: :destroy
  
  belongs_to :created_by_ethscription, primary_key: 'ethscription_id', foreign_key: 'contract_id',
    class_name: "Ethscription", touch: true
  
  NULL_ADDR = "0x0000000000000000000000000000000000000000".freeze

  def execute_function(function_name, function_args)
    abi_entry = abi[function_name]
    
    begin
      with_state_management(read_only: abi_entry.read_only?) do
        send(function_name.to_sym, function_args.deep_symbolize_keys)
      end
    rescue ContractError => e
      e.contract = self
      raise e
    end
  end
  
  def with_state_management(read_only:)
    load_current_state
  
    yield.tap do
      # binding.pry
      if state_changed? && !read_only
        states.create!(
          ethscription_id: current_transaction.ethscription.ethscription_id,
          state: @state_proxy.serialize
        )
      end
    end
  end
  
  def tx
    current_transaction.tx
  end
  
  attr_accessor :current_transaction
  
  class Transaction
    attr_accessor :contract_id, :function_name, :contract_protocol,
    :function_args, :tx, :call_receipt, :ethscription, :operation
    
    class Tx
      attr_reader :origin
      
      def origin=(address)
        @origin = TypedVariable.create(:address, address).value
      end
    end
    
    def tx
      @tx ||= Tx.new
    end
    
    def set_operation_from_ethscription
      return unless ethscription.initial_owner == NULL_ADDR
      
      mimetype = ethscription.mimetype
      match_data = mimetype.match(%q{application/vnd.esc.contract.(call|deploy)\+json})

      self.operation = match_data && match_data[1].to_sym
    end
    
    def self.create_and_execute_from_ethscription_if_needed(ethscription)
      new.import_from_ethscription(ethscription)&.execute_transaction
    end
    
    def self.make_static_call(contract_id:, function_name:, function_args: {}, msgSender: nil)
      new(
        operation: :static_call,
        function_name: function_name,
        function_args: function_args,
        contract_id: contract_id,
        msgSender: msgSender
      ).execute_static_call.as_json
    end
    
    def initialize(options = {})
      @operation = options[:operation]
      @function_name = options[:function_name]
      @function_args = options[:function_args]
      @contract_id = options[:contract_id]
      tx.origin = options[:msgSender]
    end
    
    def import_from_ethscription(ethscription)
      self.ethscription = ethscription
      set_operation_from_ethscription
      
      return unless operation.present?
      
      self.call_receipt = ContractCallReceipt.new(
        caller: ethscription.creator,
        ethscription_id: ethscription.ethscription_id,
        timestamp: ethscription.creation_timestamp
      )
      
      begin
        data = JSON.parse(ethscription.content)
      rescue JSON::ParserError => e
        return call_receipt.update!(
          error_message: "JSON::ParserError: #{e.message}"
        )
      end
      
      self.function_name = is_deploy? ? :constructor : data['functionName']
      self.function_args = data['args'] || data['constructorArgs'] || {}
      self.contract_id = data['contractId']
      self.contract_protocol = data['protocol']
      
      call_receipt.tap do |r|
        r.caller = ethscription.creator
        r.ethscription_id = ethscription.ethscription_id
        r.timestamp = ethscription.creation_timestamp
        r.function_name = function_name
        r.function_args = function_args
      end
      
      tx.origin = ethscription.creator
      
      self
    end
    
    def create_execution_context_for_call(callee_contract_id, caller_address_or_id)
      callee_contract = Contract.find_by_contract_id(callee_contract_id.to_s)
      
      if callee_contract.blank?
        raise TransactionError.new("Contract not found: #{callee_contract_id}")
      end
      
      callee_contract.msg.sender = caller_address_or_id
      callee_contract.current_transaction = self
      
      ContractProxy.new(callee_contract, operation: operation)
    end
    
    def ensure_valid_deploy!
      return unless is_deploy? && contract_id.blank?
      
      unless self.class.valid_contract_types.include?(contract_protocol)
        raise TransactionError.new("Invalid contract protocol: #{contract_protocol}")
      end
      
      contract_class = "Contracts::#{contract_protocol}".constantize
      new_contract = contract_class.create!(contract_id: ethscription.ethscription_id)
      
      self.contract_id = new_contract.contract_id
    end
    
    def initial_contract_proxy
      @initial_contract_proxy ||= create_execution_context_for_call(contract_id, tx.origin)
    end
    
    def execute_static_call
      begin
        initial_contract_proxy.send(function_name, function_args)
      rescue ContractError => e
        raise StaticCallError.new("Static Call error #{e.message}")
      end
    end
    
    def execute_transaction
      begin
        ActiveRecord::Base.transaction do
          ensure_valid_deploy!
          
          initial_contract_proxy.send(function_name, function_args).tap do
            call_receipt.status = :success
          end
        end
      rescue ContractError, TransactionError => e
        call_receipt.error_message = e.message
        call_receipt.status = is_deploy? ? :deploy_error : :call_error
      ensure
        ActiveRecord::Base.transaction do
          call_receipt.contract_id = contract_id

          call_receipt.save!
        end
      end
    end
    
    def is_deploy?
      operation == :deploy
    end
    
    def log_event(event)
      call_receipt.logs << event
    end
    
    def self.valid_contract_types
      Contracts.constants.map do |c|
        Contracts.const_get(c).to_s.demodulize
      end
    end
  end
  
  def require(condition, message)
    unless condition
      raise ContractError.new(message, self)
    end 
  end
  
  def self.public_abi
    abi.select do |name, details|
      details.publicly_callable?
    end
  end
  
  def public_abi
    self.class.public_abi
  end
  
  class Message
    attr_reader :sender
    
    def sender=(address)
      @sender = TypedVariable.create(:addressOrDumbContract, address).value
    end
  end
  
  attr_accessor :msg

  def msg
    @msg ||= Message.new
  end
  
  def abi
    self.class.abi
  end
  
  def self.abi
    @abi ||= AbiProxy.new(self)
  end
  
  class << self
    attr_accessor :parent_contracts
  end
  
  def self.parent_contracts
    @parent_contracts ||= []
  end
  
  def self.is(*constants)
    self.parent_contracts += constants.map{|i| "Contracts::#{i}".safe_constantize}
    self.parent_contracts = self.parent_contracts.uniq
  end
  
  def self.linearize_contracts(contract, processed = [])
    # Return empty array if this contract has already been processed
    return [] if processed.include?(contract)
  
    # Add this contract to a new copy of the processed array
    new_processed = processed + [contract]
  
    # Base case: return the contract itself if no parents
    return [contract] if contract.parent_contracts.empty?
  
    # Linearize the current contract by concatenating its parents
    linearized = [contract] + contract.parent_contracts.reverse.flat_map { |parent| linearize_contracts(parent, new_processed) }
  
    # Check for a valid linearization and return it, removing duplicates from right to left
    linearized.uniq { |c| raise "Invalid linearization" if linearized.rindex(c) != linearized.index(c); c }
  end
  
  def self.linearized_parents
    linearize_contracts(self)[1..-1]
  end
  
  class AbiProxy
    attr_accessor :data, :contract_class
    
    def initialize(contract_class)
      @contract_class = contract_class
      @data = {}.with_indifferent_access
      
      merge_parent_state_variables
      merge_parent_abis
      merge_parent_events
    end
    
    def parent_contracts
      contract_class.parent_contracts
    end
    
    def merge_parent_events
      parent_events = contract_class.linearized_parents.map(&:events).reverse
      contract_class.events = parent_events.reduce({}, :merge).merge(contract_class.events)
    end
    
    def merge_parent_state_variables
      parent_state_variables = contract_class.linearized_parents.map(&:state_variable_definitions).reverse
      contract_class.state_variable_definitions = parent_state_variables.reduce({}, :merge).merge(contract_class.state_variable_definitions)
    end
    
    def merge_parent_abis
      contract_class.linearized_parents.each do |parent|
        parent.abi.data.each do |name, func|
          add_function(name, func, from_parent: true, source: parent)
        end
      end
    end
    
    def add_function(name, new_function, from_parent: false, source: nil)
      existing_function = @data[name]
      
      new_function.from_parent = from_parent
      new_function.source = source
      
      if existing_function
        if existing_function.from_parent
          unless (existing_function.virtual? && new_function.override?) ||
                 (existing_function.constructor? && new_function.constructor?)
            raise "Cannot override non-constructor parent function #{name} without proper modifiers!"
          end
          
          new_function.parent_functions << existing_function
        else
          raise "Function #{name} already defined in child!"
        end
      end
    
      @data[name] = new_function
      define_method_on_class(name, new_function, contract_class)
    end
    
    def create_and_add_function(name, args, *options, returns: nil, &block)
      new_function = FunctionProxy.create(name, args, *options, returns: returns, &block)
      add_function(name, new_function)
    end
    
    def define_method_on_class(name, func_proxy, target_class)
      target_class.class_eval do
        define_method(name) do |args = nil|
          begin
            # binding.pry if name == "transferFrom"
            cooked_args = func_proxy.convert_args_to_typed_variables_struct(args)
            ret_val = FunctionContext.define_and_call_function_method(
              self, cooked_args, &func_proxy.implementation
            )
            func_proxy.convert_return_to_typed_variable(ret_val)
          rescue Contract::ArgumentError, Contract::VariableTypeError => e
            raise ContractError.new("Wrong args in #{name}: #{e.message}", self)
          end
        end
      end
      
      parent_func = func_proxy.parent_functions.first
      
      return unless parent_func
      
      super_function_name = if parent_func.constructor?
        parent_name = parent_func.source.to_s.underscore.split("/").last
        super_function_name = parent_name.upcase
      else
        "_super_#{name}"
      end
      
      return if target_class.method_defined?(super_function_name)

      target_class.class_eval do
        define_method(super_function_name) do |args = nil|
          begin
            cooked_args = parent_func.convert_args_to_typed_variables_struct(args)
            ret_val = FunctionContext.define_and_call_function_method(
              self, cooked_args, &parent_func.implementation
            )
            parent_func.convert_return_to_typed_variable(ret_val)
          rescue Contract::ArgumentError, Contract::VariableTypeError => e
            raise ContractError.new("Wrong args in #{name}: #{e.message}", self)
          end
        end
      end
    end
    
    def method_missing(name, *args, &block)
      if data.respond_to?(name)
        data.send(name, *args, &block)
      else
        binding.pry
        super
      end
    end
    
    def respond_to_missing?(name, include_private = false)
      data.respond_to?(name, include_private) || super
    end
    
    class FunctionProxy
      attr_accessor :args, :state_mutability, :visibility,
        :returns, :type, :implementation, :override_modifier,
        :from_parent, :parent_functions, :source
      
      def initialize(**opts)
        @args = opts[:args].presence
        @state_mutability = opts[:state_mutability]
        @visibility = opts[:visibility]
        @returns = opts[:returns]
        @type = opts[:type]
        @override_modifier = opts[:override_modifier]&.to_sym
        @implementation = opts[:implementation]
        @source = opts[:source]
        @from_parent = !!opts[:from_parent]
        @parent_functions = opts[:parent_functions] || []
      end
      
      def arg_names
        args.keys
      end
      
      def virtual?
        override_modifier == :virtual
      end
      
      def override?
        override_modifier == :override
      end
      
      def constructor?
        type == :constructor
      end
      
      def read_only?
        [:view, :pure].include?(state_mutability)
      end
      
      def publicly_callable?
        [:public, :external].include?(visibility) || constructor?
      end
      
      def validate_arg_names(other_args)
        return if args.nil? && other_args.blank?
        
        other_args ||= {}
        
        missing_args = arg_names - other_args.keys
        extra_args = other_args.keys - arg_names
        
        errors = [].tap do |error_messages|
          error_messages << "Missing arguments for: #{missing_args.join(', ')}." if missing_args.any?
          error_messages << "Unexpected arguments provided for: #{extra_args.join(', ')}." if extra_args.any?
        end
        
        if errors.any?
          raise ArgumentError.new(errors.join(' '))
        end
      end
      
      def convert_args_to_typed_variables_struct(other_args)
        validate_arg_names(other_args)
        
        return if other_args&.keys.blank?
        
        as_typed = other_args.each.with_object({}) do |(key, value), acc|
          type = args[key]
          acc[key.to_sym] = TypedVariable.create(type, value)
        end
        
        struct_class = Struct.new(*as_typed.keys)
        struct_class.new(*as_typed.values)
      end
      
      def convert_return_to_typed_variable(ret_val)
        return ret_val if ret_val.nil? || returns.nil?
        TypedVariable.create(returns, ret_val)
      end
      
      def self.create(name, args, *options, returns: nil, &block)
        options_hash = {
          state_mutability: :non_payable,
          visibility: :internal,
          override_modifier: nil
        }
      
        options.each do |option|
          case option
          when :payable, :nonpayable, :view, :pure
            options_hash[:state_mutability] = option
          when :public, :external, :private
            options_hash[:visibility] = option
          when :override, :virtual
            options_hash[:override_modifier] = option
          end
        end
        
        new(
          args: args,
          state_mutability: options_hash[:state_mutability],
          override_modifier: options_hash[:override_modifier],
          visibility: name == :constructor ? nil : options_hash[:visibility],
          returns: returns,
          type: name == :constructor ? :constructor : :function,
          implementation: block
        )
      end
    end
  end
  
  class FunctionContext < BasicObject
    include ::Kernel
    attr_reader :contract, :args
    
    def initialize(contract, args)
      @contract = contract
      @args = args
    end
  
    def method_missing(name, *args, **kwargs, &block)
      if @args.respond_to?(name)
        @args.send(name, *args, **kwargs, &block)
      else
        @contract.send(name, *args, **kwargs, &block)
      end
    end
    
    def this
      @contract
    end
    
    def require(*args)
      @contract.send(:require, *args)
    end
  
    def respond_to_missing?(name, include_private = false)
      @args.respond_to?(name, include_private) || @contract.respond_to?(name, include_private)
    end
    
    def self.define_and_call_function_method(contract, args, &block)
      context = new(contract, args)
      # binding.pry
      context.define_singleton_method(:function_implementation, &block)
      context.function_implementation
    end
  end
    
  def self.function(name, args, *options, returns: nil, &block)
    abi.create_and_add_function(name, args, *options, returns: returns, &block)
  end
  
  def self.constructor(args, *options, &block)
    function(:constructor, args, *options, returns: nil, &block)
  end
  
  def self.all_abis
    contract_classes = valid_contract_types

    contract_classes.each_with_object({}) do |contract_class, hash|
      hash[contract_class.name] = contract_class.public_abi
    end.transform_keys(&:demodulize)
  end
  
  def self.event(name, args)
    @events ||= {}
    @events[name] = args
  end

  def self.events
    @events || {}
  end
  
  def self.events=(others)
    @events = others
  end

  def emit(event_name, args = {})
    unless self.class.events.key?(event_name)
      raise ContractDefinitionError.new("Event #{event_name} is not defined in this contract.", self)
    end

    expected_args = self.class.events[event_name]
    missing_args = expected_args.keys - args.keys
    extra_args = args.keys - expected_args.keys

    if missing_args.any? || extra_args.any?
      error_messages = []
      error_messages << "Missing arguments for #{event_name} event: #{missing_args.join(', ')}." if missing_args.any?
      error_messages << "Unexpected arguments provided for #{event_name} event: #{extra_args.join(', ')}." if extra_args.any?
      raise ContractDefinitionError.new(error_messages.join(' '), self)
    end

    current_transaction.log_event({ event: event_name, data: args })
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :contract_id,
        ]
      )
    ).tap do |json|
      json['abi'] = public_abi.as_json
      
      json['current_state'] = current_state.state
      json['current_state']['contract_type'] = type.demodulize
    end
  end
  
  class << self
    attr_accessor :state_variable_definitions
  end

  def self.state_variable_definitions
    @state_variable_definitions ||= {}
  end
  
  def s
    @state_proxy
  end
  
  after_initialize :initialize_state_proxy
  
  def initialize_state_proxy
    @state_proxy = StateProxy.new(self, self.class.state_variable_definitions)
  end
  
  def current_state
    states.newest_first.first || ContractState.new
  end
  
  def load_current_state
    @state_proxy.deserialize(current_state.state.deep_dup)
    @initial_state = @state_proxy.serialize
    self
  end
  
  def state_changed?
    @initial_state != @state_proxy.serialize
  end
  
  def self.define_state_variable(type, args)
    name = args.last.to_sym
    type = Type.create(type)
    
    if state_variable_definitions[name]
      raise "No shadowing: #{name} is already defined."
    end
    
    state_variable_definitions[name] = { type: type, args: args }
    
    state_var = StateVariable.create(name, type, args)
    state_var.create_public_getter_function(self)
  end
  
  class StateProxy
    attr_reader :contract
    attr_reader :state_variables
    
    def initialize(contract, definitions)
      @contract = contract
      @state_variables = {}.with_indifferent_access
      
      definitions.each do |name, definition|
        @state_variables[name] = StateVariable.create(name, definition[:type], definition[:args])
      end
    end
    
    def method_missing(name, *args)
      is_setter = name[-1] == '='
      var_name = is_setter ? name[0...-1].to_s : name.to_s
      
      var = state_variables[var_name]
      
      return super if var.nil?
      
      return var.typed_variable unless is_setter
        
      begin
        var.typed_variable.value = args.first
      rescue StateVariableMutabilityError => e
        message = "immutability error for #{var_name}: #{e.message}"
        raise ContractRuntimeError.new(message, contract)
      rescue StateVariableTypeError => e
        raise ContractRuntimeError.new(e.message, contract)
      end
    end
    
    def serialize
      state_variables.each.with_object({}) do |(key, value), h|
        h[key] = value.serialize
      end
    end
    
    def deserialize(state_data)
      state_data.each do |var_name, value|
        state_variables[var_name.to_sym].deserialize(value)
      end
    end
  end
  
  class StateVariable
    attr_accessor :typed_variable, :name, :visibility, :immutable, :constant
    
    def initialize(name, typed_variable, args)
      visibility = :internal
      
      args.each do |arg|
        case arg
        when :public, :private
          visibility = arg
        end
      end
      
      @visibility = visibility
      @immutable = args.include?(:immutable)
      @constant = args.include?(:constant)
      @name = name
      @typed_variable = typed_variable
    end
    
    def self.create(name, type, args)
      var = TypedVariable.create(type)
      new(name, var, args)
    end
    
    def create_public_getter_function(contract_class)
      return unless @visibility == :public
      new_var = self
      
      if type.mapping?
        create_mapping_getter_function(contract_class)
      else
        contract_class.class_eval do
          self.function(new_var.name, {}, :public, :view, returns: new_var.type.name) do
            s.send(new_var.name)
          end
        end
      end
    end
    
    def create_mapping_getter_function(contract_class)
      arguments = {}
      current_type = type
      index = 1
      new_var = self
      
      while current_type.name == :mapping
        arguments["_#{index}".to_sym] = current_type.key_type.name
        current_type = current_type.value_type
        index += 1
      end
      
      contract_class.class_eval do
        self.function(new_var.name, arguments, :public, :view, returns: current_type.name) do
          value = s.send(new_var.name)
          (1...index).each do |i|
            value = value[send("_#{i}".to_sym)]
          end
          value
        end
      end
    end
    
    def serialize
      typed_variable.serialize
    end
    
    def deserialize(value)
      typed_variable.deserialize(value)
    end
    
    def method_missing(name, *args, &block)
      if typed_variable.respond_to?(name)
        typed_variable.send(name, *args, &block)
      else
        super
      end
    end
  
    def respond_to_missing?(name, include_private = false)
      typed_variable.respond_to?(name, include_private) || super
    end
    
    def ==(other)
      other.is_a?(self.class) &&
        typed_variable == other.typed_variable &&
        name == other.name &&
        visibility == other.visibility &&
        immutable == other.immutable &&
        constant == other.constant
    end
    
    def !=(other)
      !(self == other)
    end
    
    def hash
      [typed_variable, name, visibility, immutable, constant].hash
    end

    def eql?(other)
      hash == other.hash
    end
  end
  
  class TypedVariable
    attr_accessor :type, :value

    def initialize(type, value = nil, **options)
      self.type = type
      self.value = value || type.default_value
    end
    
    def self.create(type, value = nil, **options)
      type = Contract::Type.create(type)
      
      if type.mapping?
        Mapping.new(type, value, **options)
      else
        new(type, value, **options)
      end
    end
    
    def as_json(args = {})
      serialize
    end
    
    def serialize
      value
    end
    
    def to_s
      value.is_a?(String) ? value : super
    end
    
    def deserialize(serialized_value)
      self.value = serialized_value
    end
    
    def value=(new_value)
      @value = if new_value.is_a?(TypedVariable)
        if new_value.type != type
          raise VariableTypeError.new("invalid #{type}: #{new_value.value}")
        end
        
        new_value.value
      else
        type.check_and_normalize_literal(new_value)
      end
    end
    
    def method_missing(name, *args, &block)
      if value.respond_to?(name)
        result = value.send(name, *args, &block)
        
        if name.to_s.end_with?("=") && !%w[>= <=].include?(name.to_s[-2..])
          self.value = result if type.is_value_type?
          self
        else
          result
        end
      else
        binding.pry
        super
      end
    end
  
    def respond_to_missing?(name, include_private = false)
      value.respond_to?(name, include_private) || super
    end
    
    def !=(other)
      !(self == other)
    end
    
    def ==(other)
      other.is_a?(self.class) &&
      value == other.value &&
      type == other.type
    end
    
    def hash
      [value, type].hash
    end

    def eql?(other)
      hash == other.hash
    end
  end
  
  class Mapping < TypedVariable
    def initialize(type, value = nil, **options)
      super
    end
    
    def serialize
      value.data.each.with_object({}) do |(key, value), h|
        h[key.serialize] = value.serialize
      end
    end
    
    class Proxy
      attr_accessor :key_type, :value_type, :data
      
      def initialize(initial_value = {}, key_type:, value_type:)
        self.key_type = key_type
        self.value_type = value_type
        
        self.data = initial_value
      end
      
      def [](key_var)
        key_var = TypedVariable.create(key_type, key_var)
        value = data[key_var]
  
        if value_type.mapping? && value.nil?
          value = TypedVariable.create(value_type)
          data[key_var] = value
        end
  
        value || TypedVariable.create(value_type)
      end

      def []=(key_var, value)
        key_var = TypedVariable.create(key_type, key_var)
        val_var = TypedVariable.create(value_type, value)
  
        if value_type.mapping?
          val_var = Proxy.new(key_type: value_type.key_type, value_type: value_type.value_type)
          raise "What?"
        end
  
        self.data[key_var] ||= val_var
        self.data[key_var].value = val_var.value
      end
    end
  end
  
  class Type
    attr_accessor :name, :metadata, :key_type, :value_type
    
    TYPES = [:string, :mapping, :address, :dumbContract,
            :addressOrDumbContract,
            :bool, :bytes, :address]
    # TODO: Arrays
    (8..256).step(8) do |n|
      TYPES << "uint#{n}".to_sym
      TYPES << "int#{n}".to_sym
      TYPES << "bytes#{n / 8}".to_sym
    end
    
    TYPES.each do |type|
      define_method("#{type}?") do
        self.name == type
      end
    end
    
    def self.value_types
      TYPES.select do |type|
        create(type).is_value_type?
      end
    end
    
    def initialize(type_name, metadata = {})
      type_name = type_name.to_sym
      
      if TYPES.exclude?(type_name)
        raise "Invalid type #{name}"
      end
      
      self.name = type_name.to_sym
      self.metadata = metadata
    end
    
    def self.create(type_or_name, metadata = {})
      return type_or_name if type_or_name.is_a?(self)
      
      new(type_or_name, metadata) rescue binding.pry
    end
    
    def key_type=(type)
      return if type.nil?
      @key_type = self.class.create(type)
    end
    
    def value_type=(type)
      return if type.nil?
      @value_type = self.class.create(type)
    end
    
    def metadata=(metadata)
      self.key_type = metadata[:key_type]
      self.value_type = metadata[:value_type]
    end
    
    def metadata
      { key_type: key_type, value_type: value_type }
    end
    
    def to_s
      name.to_s
    end
    
    def int_or_uint?
      name.to_s.match(/^u?int/)
    end
    
    def default_value
      return 0 if int_or_uint?
      return NULL_ADDR if address? || addressOrDumbContract?
      return "0x" + "0" * 64 if dumbContract?
      return '' if string?
      return false if bool?
      return Contract::Mapping::Proxy.new(key_type: key_type, value_type: value_type) if mapping?
      raise "Unknown default value for #{self.inspect}"
    end
    
    def check_and_normalize_literal(literal)
      if address?
        unless literal.is_a?(String) && literal.match?(/^0x[a-f0-9]{40}$/i)
          raise VariableTypeError.new("invalid address: #{literal}")
        end
        
        return literal.downcase
      # elsif name.to_s.match(/^uint/)
      elsif uint256?
        if literal.is_a?(String) && literal.match?(/^[1-9]\d*$/)
          return literal.to_i
        elsif literal.is_a?(Integer) && literal.between?(0, 2 ** 256 - 1)
          return literal
        end
        
        raise VariableTypeError.new("invalid #{self}: #{literal}")
      elsif string?
        unless literal.is_a?(String)
          raise VariableTypeError.new("invalid #{self}: #{literal}")
        end
        
        return literal
      elsif bool?
        unless literal == true || literal == false
          raise VariableTypeError.new("invalid #{self}: #{literal}")
        end
        
        return literal
      elsif dumbContract?
        unless literal.is_a?(String) && literal.match?(/^0x[a-f0-9]{64}$/i)
          raise VariableTypeError.new("invalid #{self}: #{literal}")
        end
        
        return literal.downcase
      elsif addressOrDumbContract?
        unless literal.is_a?(String) && (literal.match?(/^0x[a-f0-9]{64}$/i) || literal.match?(/^0x[a-f0-9]{40}$/i))
          raise VariableTypeError.new("invalid #{self}: #{literal}")
        end
        
        return literal.downcase
      elsif mapping?
        if literal.is_a?(Contract::Mapping::Proxy)
          return literal
        end
        
        unless literal.is_a?(Hash)
          raise VariableTypeError.new("invalid #{literal}")
        end
        
        data = literal.map do |key, value|
          [
            TypedVariable.create(key_type, key),
            TypedVariable.create(value_type, value)
          ]
        end.to_h
      
        proxy = Contract::Mapping::Proxy.new(data, key_type: key_type, value_type: value_type)
        
        return proxy
      end
      # binding.pry
      raise VariableTypeError.new("Unknown type #{self.inspect} : #{literal}")
    end
    
    def ==(other)
      other.is_a?(self.class) &&
      other.name == name &&
      other.metadata == metadata
    end
    
    def !=(other)
      !(self == other)
    end
    
    def hash
      [name, metadata].hash
    end

    def eql?(other)
      hash == other.hash
    end
    
    def is_value_type?; !mapping?; end
  end
  
  def self.pragma(*args)
    # Do nothing for now
  end
  
  Contract::Type.value_types.each do |type|
    define_singleton_method(type) do |*args|
      define_state_variable(type, args)
    end
  end
  
  def self.mapping(*args)
    key_type, value_type = args.first.first
    metadata = {key_type: key_type, value_type: value_type}
    type = Contract::Type.create(:mapping, metadata)
    
    if args.last.is_a?(Symbol)
      define_state_variable(type, args)
    else
      type
    end
  end
  
  protected

  def address(i)
    return NULL_ADDR if i == 0
    raise "Not implemented"
  end
  
  def DumbContract(contract_id)
    current_transaction.create_execution_context_for_call(contract_id, self.contract_id)
  end
  
  def dumbContractId(i)
    return contract_id if i == self
    raise "Not implemented"
  end
end
