class AbiProxy
  include ContractErrors
  
  attr_accessor :data, :contract_class
  
  def initialize(contract_class)
    @contract_class = contract_class
    @data = {}.with_indifferent_access
    
    merge_parent_state_variables
    merge_parent_abis
    merge_parent_events
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
        prefixed_name = "__#{parent.name}__#{name}"
        define_function_method(prefixed_name, func, contract_class)
        add_function(name, func, from_parent: true)
      end
    end
  end
  
  def add_function(name, new_function, from_parent: false)
    existing_function = @data[name]
    
    new_function.from_parent = from_parent
    
    if existing_function
      if existing_function.from_parent
        unless (existing_function.virtual? && new_function.override?) ||
               (existing_function.constructor? && new_function.constructor?) ||
               from_parent
          raise InvalidOverrideError, "Cannot override non-constructor parent function #{name} without proper modifiers (#{contract_class.name})"
        end
      else
        raise FunctionAlreadyDefinedError, "Function #{name} already defined in child!"
      end
    elsif new_function.override?
      raise InvalidOverrideError, "Function #{name} declared with override but does not override any parent function (#{contract_class.name})"
    end
  
    @data[name] = new_function
    define_function_method(name, new_function, contract_class)
  end
  
  def create_and_add_function(name, args, *options, returns: nil, &block)
    new_function = FunctionProxy.create(name, args, *options, returns: returns, &block)
    add_function(name, new_function)
  end
  
  private
  
  def define_function_method(method_name, func_proxy, target_class)
    target_class.class_eval do
      define_method(method_name) do |*args, **kwargs|
        begin
          cooked_args = func_proxy.convert_args_to_typed_variables_struct(args, kwargs)
          
          ret_val = nil
          
          state_proxy.detecting_changes(revert_on_change: func_proxy.read_only?) do
            ret_val = FunctionContext.define_and_call_function_method(
              self, cooked_args, &func_proxy.implementation
            )
          end
          
          func_proxy.convert_return_to_typed_variable(ret_val)
        rescue Contract::ContractArgumentError, Contract::VariableTypeError => e
          raise ContractError.new("Wrong args in #{method_name} (#{func_proxy.func_location}): #{e.message}", self)
        rescue InvalidStateVariableChange
          raise ContractError,
          "Invalid change in read-only function: #{method_name}, #{(args.presence || kwargs).inspect}, to address: #{current_address}."
        end
      end
    end
  end
  
  def method_missing(name, *args, &block)
    if data.respond_to?(name)
      data.send(name, *args, &block)
    else
      super
    end
  end
  
  def respond_to_missing?(name, include_private = false)
    data.respond_to?(name, include_private) || super
  end
  
  class FunctionProxy
    include ContractErrors
    
    attr_accessor :args, :state_mutability, :visibility,
      :returns, :type, :implementation, :override_modifiers,
      :from_parent
    
    def initialize(**opts)
      @args = opts[:args] || {}
      @state_mutability = opts[:state_mutability]
      @visibility = opts[:visibility]
      @returns = opts[:returns]
      @type = opts[:type]
      @override_modifiers = Array.wrap(opts[:override_modifiers]).uniq.map{|i| i.to_sym}
      @implementation = opts[:implementation]
      @from_parent = !!opts[:from_parent]
    end
    
    def arg_names
      args.keys
    end
    
    def virtual?
      override_modifiers.include?(:virtual)
    end
    
    def override?
      override_modifiers.include?(:override)
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
    
    def func_location
      implementation.source_location.join(":")
    end
    
    def validate_arg_names(other_args)
      if other_args.is_a?(Hash)
        missing_args = arg_names - other_args.keys
        extra_args = other_args.keys - arg_names
      elsif other_args.is_a?(Array)
        missing_args = arg_names.size > other_args.size ? arg_names.last(arg_names.size - other_args.size) : []
        extra_args = other_args.size > arg_names.size ? other_args.last(other_args.size - arg_names.size) : []
      else
        raise ArgumentError, "Expected Hash or Array, got #{other_args.class}"
      end
      
      errors = [].tap do |error_messages|
        error_messages << "Missing arguments for: #{missing_args.join(', ')}." if missing_args.any?
        error_messages << "Unexpected arguments provided for: #{extra_args.join(', ')}." if extra_args.any?
      end
      
      if errors.any?
        raise ContractArgumentError.new(errors.join(' '))
      end
    end
    
    def convert_args_to_typed_variables_struct(other_args, other_kwargs)
      if other_kwargs.present?
        other_args = other_kwargs.deep_symbolize_keys
      end
      
      if other_args.first.is_a?(Hash) && other_args.length == 1
        other_args = other_args.first.deep_symbolize_keys
      end
      
      validate_arg_names(other_args)
      
      return Struct.new(nil).new if args.blank?
      
      as_typed = if other_args.is_a?(Array)
        args.keys.zip(other_args).map do |key, value|
          type = args[key]
          [key, TypedVariable.create_or_validate(type, value)]
        end.to_h
      else
        other_args.each.with_object({}) do |(key, value), acc|
          type = args[key]
          acc[key.to_sym] = TypedVariable.create_or_validate(type, value)
        end
      end
      
      struct_class = Struct.new(*as_typed.keys)
      struct_class.new(*as_typed.values)
    end
    
    def convert_return_to_typed_variable(ret_val)
      return nil if constructor?
      
      if returns.nil?
        return nil if ret_val.nil?
        
        raise ContractError, "Function #{func_location} returned #{ret_val.inspect}, but expected nil"
      end
    
      if ret_val.nil?
        raise ContractError, "Function #{func_location} returned nil, but expected #{returns}"
      end
      
      if returns.is_a?(Hash)
        ret_val.each.with_object({}) do |(key, value), acc|
          acc[key.to_sym] = TypedVariable.create_or_validate(returns[key], value)
        end
        DestructureOnly.new(ret_val)
      else
        TypedVariable.create_or_validate(returns, ret_val)
      end
    end
    
    def self.create(name, args, *options, returns: nil, &block)
      options_hash = {
        state_mutability: :non_payable,
        visibility: :internal,
        override_modifiers: []
      }
    
      options.each do |option|
        case option
        when :payable, :nonpayable, :view, :pure
          options_hash[:state_mutability] = option
        when :public, :external, :private
          options_hash[:visibility] = option
        when :override, :virtual
          options_hash[:override_modifiers] << option
        end
      end
      
      new(
        args: args,
        state_mutability: options_hash[:state_mutability],
        override_modifiers: options_hash[:override_modifiers],
        visibility: name == :constructor ? nil : options_hash[:visibility],
        returns: returns,
        type: name == :constructor ? :constructor : :function,
        implementation: block
      )
    end
  end
  
  class DestructureOnly
    include ContractErrors
    
    def initialize(hash)
      @hash = hash
    end
  
    def to_ary
      if @destructured
        raise InvalidDestructuringError, "This object has already been destructured and cannot be used again"
      else
        @destructured = true
        @hash.values
      end
    end
  
    def as_json(*)
      @hash.as_json
    end
  
    private
  
    def method_missing(name, *args, &block)
      raise InvalidDestructuringError, "This object must be destructured immediately and cannot be used as a regular object"
    end
  end
end
