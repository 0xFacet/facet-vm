class FalseClass
  def on_change=(*)
  end
  
  def type
    Type.create(:bool)
  end
  
  def on_change
    -> {}
  end
  
  def serialize
    self
  end
  
  def deserialize(*)
  end
  
  def value
    self
  end
  
  def value=(new_val)
    unless new_val == self
      raise "Cannot change value of false"
    end
  end
end

class TrueClass
  def on_change=(*)
  end
  
  def type
    Type.create(:bool)
  end
  
  def on_change
    -> {}
  end
  
  def serialize
    self
  end
  
  def deserialize(*)
  end
  
  def value
    self
  end
  
  def value=(new_val)
    unless new_val == self
      raise "Cannot change value of true"
    end
  end
end
