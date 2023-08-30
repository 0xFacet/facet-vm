class String
  def cast(type)
    TypedVariable.create(type, self)
  end
end

class Integer
  def cast(type)
    TypedVariable.create(type, self)
  end
end
