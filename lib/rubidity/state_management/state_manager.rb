class StateManager
  include ContractErrors
  
  attr_reader :state_variables, :unused_variables
  attr_accessor :state_changed
  
  def initialize(definitions)
    @state_variables = {}.with_indifferent_access
    @unused_variables = {}.with_indifferent_access
    @dirty_stack = []
    
    definitions.each do |name, definition|
      @state_variables[name] = StateVariable.create(
        name,
        definition[:type],
        definition[:args],
        on_change: method(:mark_dirty)
      )
    end
  end
  
  def state_proxy
    @state_proxy ||= StateProxy.new(self)
  end
  
  def detecting_changes(revert_on_change:)
    @dirty_stack.push(false)
    
    yield
    
    if @dirty_stack.last && revert_on_change
      raise InvalidStateVariableChange.new
    end
  ensure
    @dirty_stack.pop
  end
  
  def clear_changed
    self.state_changed = false
  end
  
  def serialize(dup: true)
    val = state_variables.each.with_object({}) do |(key, value), h|
      h[key] = value.serialize
    end.reverse_merge(unused_variables)
    
    dup ? val.deep_dup : val
  end
  
  def deserialize(state_data)
    state_data.each do |var_name, value|
      if var = state_variables[var_name]
        var.deserialize(value)
      else
        unused_variables[var_name] = value
      end
    end
  end
  alias_method :load, :deserialize
  
  private
  
  def mark_dirty
    self.state_changed = true
    
    return if @dirty_stack.empty?
    
    @dirty_stack[-1] = true
  end
end
