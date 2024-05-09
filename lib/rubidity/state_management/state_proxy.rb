class StateProxy < BoxedVariable
  def initialize(manager)
    @manager = manager
  end
  
  def method_missing(name, *args)
    args = ::VM.deep_unbox(args)
    
    is_setter = name.end_with?('=')
    var_name = name.to_s.chomp("=")
    
    var = @manager.state_variables[var_name]
    
    return super if var.nil?
    return super if !is_setter && args.present?
    return super if is_setter && args.length != 1
    
    if is_setter
      var.typed_variable = args.first
    else
      var.typed_variable
    end
  end
end
