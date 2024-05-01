class StateProxy #< UltraBasicObject
  def initialize(manager)
    @manager = manager
  end
  
  def method_missing(name, *args)
    is_setter = name.end_with?('=')
    var_name = name.to_s.chomp("=")
    
    var = @manager.state_variables[var_name]
    
    return super if var.nil?
    return super if !is_setter && args.present?
    return super if is_setter && args.length != 1
    
    if is_setter
      other_var = ::TypedVariableProxy.get_typed_variable(args.first)
      
      ::TypedVariableProxy.new(var.typed_variable = other_var)
    else
      ::TypedVariableProxy.new(var.typed_variable)
    end
  rescue => e
    binding.pry
    raise
  end
end
