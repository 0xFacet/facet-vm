module BooleanExtensions
  include TypedObject

  def type
    Type.new(:bool)
  end
  
  def value=(*)
    raise TypeError.new("Cannot change value of #{self}")
  end
  
  def deserialize(*)
    raise TypeError.new("Cannot deserialize #{self}")
  end
end

class FalseClass
  include BooleanExtensions
end

class TrueClass
  include BooleanExtensions
end
