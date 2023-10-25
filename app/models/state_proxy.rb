class StateProxy
  include ContractErrors
  
  attr_reader :state_variables
  
  def initialize(definitions)
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
    sorted = state_variables.sort_by { |key, _| [key.length, key] }.to_h
    
    sorted.each.with_object({}) do |(key, value), h|
      h[key] = value.serialize
    end.deep_dup
  end
  
  def deserialize(state_data)
    state_data.deep_dup.each do |var_name, value|
      var = state_variables[var_name.to_sym]
      
      unless var
        raise "Unknown state variable #{var_name}"
      end
      
      var.deserialize(value)
    end
    
    @initial_state ||= serialize
  end
  alias_method :load, :deserialize
  
  def state_changed?
    @initial_state != serialize
  end
end
