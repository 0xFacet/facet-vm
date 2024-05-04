class BoxedVariable # < UltraBasicObject
  def initialize(value = nil)
    @value = value
  end

  def unbox
    @value
  end
  
  def to_ary
    if @value.is_a?(Array)
      @value.to_ary
    else
      raise "Cannot convert to array: #{@value.inspect}"
    end
  end
end
