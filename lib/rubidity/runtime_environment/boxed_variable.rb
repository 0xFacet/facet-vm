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
end
