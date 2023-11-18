module TypedObject
  def on_change
  end
  
  def on_change=(*)
  end

  def serialize
    value
  end

  def value
    self
  end
end
