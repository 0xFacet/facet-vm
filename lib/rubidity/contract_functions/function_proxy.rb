class FunctionProxy
  include ContractErrors
  
  attr_accessor :args, :state_mutability, :visibility,
    :returns, :type, :implementation, :override_modifiers,
    :from_parent, :contract_class
  
  def create_type(...)
    contract_class&.create_type(...) || Type.create(...)
  end
    
  def initialize(**opts)
    @args = opts[:args] || {}
    @state_mutability = opts[:state_mutability]
    @visibility = opts[:visibility]
    @returns = opts[:returns]
    @type = opts[:type]
    @override_modifiers = Array.wrap(opts[:override_modifiers]).uniq.map{|i| i.to_sym}
    @implementation = opts[:implementation]
    @from_parent = !!opts[:from_parent]
    @contract_class = opts[:contract_class]
  end
  
  def as_json
    {
      inputs: args_for_json,
      overrideModifiers: override_modifiers,
      outputs: returns_for_json,
      stateMutability: state_mutability,
      type: type,
      visibility: visibility,
      fromParent: from_parent,
    }.with_indifferent_access
  end
  
  def args_for_json
    args.stringify_keys.map do |name, type|
      type = create_type(type)
      
      if type.array?
        { name: name, type: "#{type.value_type}[#{type.initial_length}]" }
      elsif type.is_value_type?
        { name: name, type: type.name.to_s }
      elsif type.struct?
        {
          name: name,
          type: 'tuple',
          internalType: "struct #{contract_class.name}.#{type.name}",
          components: type.struct_definition.fields.map do |field_name, field_type|
            {
              name: field_name,
              type: field_type[:type].name.to_s,
              internalType: field_type[:type].name.to_s,
            }
          end
        }
      else
        raise "Invalid ABI serialization"
      end
    end
  end
  
  def returns_for_json
    return [] if returns.nil?
    
    if returns.is_a?(Hash)
      returns.stringify_keys.map do |name, type|
        type = create_type(type)
        { name: name, type: type.name.to_s }
      end
    else
      type = create_type(returns)
      
      if contract_class&.structs[type.name]
        [{
          name: type.name,
          type: 'tuple',
          internalType: "struct #{contract_class.name}.#{type.name}",
          components: type.struct_definition.fields.map do |field_name, field_type|
            {
              name: field_name,
              type: field_type[:type].name.to_s,
              internalType: field_type[:type].name.to_s,
            }
          end
        }]
      else
        [{ type: type.name.to_s }]
      end
    end
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
    
    return ContractFunctionArgs.new if args.blank?
        
    as_typed = if other_args.is_a?(Array)
      args.keys.zip(other_args).map do |key, value|
        type = args[key]
        [key, TypedVariable.create_or_validate(create_type(type), value)]
      end.to_h
    else
      other_args.each.with_object({}) do |(key, value), acc|
        type = args[key]
        acc[key.to_sym] = TypedVariable.create_or_validate(create_type(type), value)
      end
    end
    
    ContractFunctionArgs.new(as_typed)
  end
  
  def convert_return_to_typed_variable(ret_val)
    return NullVariable.instance if constructor?
    
    ret_val = VM.deep_unbox(ret_val)
    
    if returns.nil?
      if ret_val.eq(NullVariable.instance)
        return NullVariable.instance
      end
      
      raise ContractError, "Function #{func_location} returned #{ret_val.inspect}, but expected null"
    end
  
    if ret_val.nil?
      raise ContractError, "Function #{func_location} returned nil, but expected #{returns}"
    end
    
    if returns.is_a?(Hash)
      ret_val = ret_val.each.with_object({}) do |(key, value), acc|
        acc[key.to_sym] = TypedVariable.create_or_validate(create_type(returns[key]), value)
      end
      DestructureOnly.new(ret_val)
    else
      TypedVariable.create_or_validate(create_type(returns), ret_val)
    end
  end
  
  def validate_args!
    args.values.each do |type|
      create_type(type)
    end
    
    return unless returns.present?
    
    if returns.is_a?(Hash)
      returns.values.each{|i| create_type(i)}
    else
      create_type(returns)
    end
  rescue TypeError => e
    raise ContractDefinitionError.new(e.message)
  end
  
  def self.create(name, args, *options, returns: nil, contract_class: nil, &block)
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
      implementation: block,
      contract_class: contract_class
    ).tap do |record|
      record.validate_args!
    end
  end
end
