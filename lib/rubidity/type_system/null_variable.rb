class NullVariable < TypedVariable
  def initialize
    @type = Type.create(:null)
    @value = nil
  end
  
  def self.instance
    @instance ||= new
  end
  
  def !
    raise TypeError.new("Call not() instead of !")
  end
  
  def ==(a)
    raise TypeError.new("Call eq() instead of ==()")
  end
  
  def ne(other)
    (self.eq(other)).not
  end
  
  def eq(other)
    unless other.is_a?(TypedVariable)
      raise ContractError.new("Cannot compare TypedVariable with #{other.class}")
    end
    
    unless type == other.type
      raise ContractError.new("Cannot compare #{type.name} with #{other.type.name}")
    end
    
    TypedVariable.create(:bool, value == other.value)
  end
end
