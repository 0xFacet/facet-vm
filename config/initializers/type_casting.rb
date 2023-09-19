class String
  def cast(type)
    TypedVariable.create(type, self)
  end
end

class Integer
  def cast(type)
    TypedVariable.create(type, self)
  end
  
  def ether
    self * 1e18.to_i
  end
end
