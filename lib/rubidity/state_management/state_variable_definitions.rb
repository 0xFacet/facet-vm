module StateVariableDefinitions
  class InvalidStateVariableDefinition < RuntimeError; end
  
  ::Type.value_types.each do |type|
    define_method(type) do |*args|
      define_state_variable(type, args)
    end
  end
  
  def mapping(*args)
    key_type, value_type = args.first.first
    metadata = {key_type: create_type(key_type), value_type: create_type(value_type)}
    type = ::Type.create(:mapping, metadata)
    
    if args.last.is_a?(::Symbol)
      define_state_variable(type, args)
    else
      type
    end
  end
  
  def array(*args, **kwargs)
    value_type = args.first
    metadata = {value_type: create_type(value_type)}.merge(kwargs)
    
    if args.length == 2
      metadata.merge!(initial_length: args.last)
      args.pop
    end
    
    type = ::Type.create(:array, metadata)
    
    if args.length == 1
      type
    else
      define_state_variable(type, args)
    end
  end
  
  def struct(name, &block)
    @structs ||= {}.with_indifferent_access
    @structs[name] = ::StructDefinition.new(name, &block)

    define_method(name) do |**field_values|
      struct_definition = self.structs[name]
      type = ::Type.create(:struct, struct_definition: struct_definition)
      ::StructVariable.new(type, field_values)
    end
    
    expose(name)
    
    define_singleton_method(name) do |*args|
      struct_definition = structs[name]
      type = ::Type.create(:struct, struct_definition: struct_definition)
      define_state_variable(type, args)
    end
  end
  
  private
  
  def define_state_variable(type, args)
    args = VM.deep_get_values(args)
    
    name = args.last.to_sym
    type = ::Type.create(type)
    
    validate_name_format!(name)
    
    if state_variable_definitions[name]
      raise InvalidStateVariableDefinition,"No shadowing: #{name} is already defined."
    end
    
    state_variable_definitions[name] = { type: type, args: args }
    
    state_var = ::StateVariable.create(name, type, args)
    state_var.create_public_getter_function(self)
  end
  
  def validate_name_format!(name)
    if name.starts_with?("__") && name.ends_with?("__")
      raise InvalidStateVariableDefinition,"Invalid name format: #{name}"
    end
    
    unless name.to_s =~ /\A[a-z_][a-z0-9_]*\z/i
      raise InvalidStateVariableDefinition,"Invalid name format: #{name}"
    end
    
    methods = (StateManager.instance_methods + StateManager.private_instance_methods)
    
    if methods.include?(name.to_sym)
      raise InvalidStateVariableDefinition, "Invalid name format: #{name}"
    end
  end
end

