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
        rescue Contract::ContractArgumentError, Contract::VariableTypeError => e
          func_location = func_proxy.implementation.to_s.gsub(%r(.*/app/models/contracts/), '').chop
          raise ContractError.new("Wrong args in #{name} (#{func_location}): #{e.message}", self)
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
        rescue Contract::ContractArgumentError, Contract::VariableTypeError => e
          func_location = parent_func.implementation.to_s.gsub(%r(.*/app/models/contracts/), '').chop
          raise ContractError.new("Wrong args in #{name} (#{func_location}): #{e.message}", self)
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
    include ContractErrors
    
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
        raise ContractArgumentError.new(errors.join(' '))
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
