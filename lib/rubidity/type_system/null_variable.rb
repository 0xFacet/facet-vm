class NullVariable < TypedVariable
  def initialize
    @type = Type.create(:null)
    @value = nil
  end
  
  class << self
    def instance
      new.freeze
    end
    memoize :instance
  end
  
  def !
    raise TypeError.new("Call not() instead of !")
  end
  
  def ==(a)
    raise TypeError.new("Call eq() instead of ==()")
  end
  
  def value=(value)
    raise TypeError.new("Cannot set value of NullVariable")
  end
  
  def ne(other)
    (self.eq(other)).not
  end
  
  def eq(other)
    TypedVariable.create(:bool, object_id == other.object_id)
  end
end
