module BooleanExtensions
  include TypedObject

  def type
    Type.new(:bool)
  end
  
  def value=(new_val)
    raise TypeError.new("Cannot change value of #{self}")
  end
end

class FalseClass
  include BooleanExtensions
end

class TrueClass
  include BooleanExtensions
end
