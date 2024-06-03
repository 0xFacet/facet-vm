class BoxedVariable < UltraBasicObject
  def initialize(value = nil)
    @value = value
  end
  
  def to_ary
    if ::VM.call_is_a?(@value, ::Array) || @value.method_exposed?(:to_ary)
      @value.to_ary
    else
      ::VM.call_method(self, :raise, args: "Cannot convert to array: #{::VM.call_method(@value, :inspect)}")
    end
  end
  
  def min
    vals = ::VM.deep_unbox(@value)
    
    unless vals.all? { |v| v.is_a?(::IntegerVariable) }
      raise "Cannot find min of non-integer values: #{vals.map(&:inspect)}"
    end
    
    vals.min_by(&:value)
  end
end
