class StateProxy
  include ContractErrors
  
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

    if is_setter
      var.typed_variable = args.first
    else
      var.typed_variable
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
  alias_method :load, :deserialize
end
