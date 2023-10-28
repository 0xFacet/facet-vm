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
    (self.to_d * 1e18.to_d).to_i
  end
end

class Float
  def ether
    to_d.to_i.ether
  end
end
