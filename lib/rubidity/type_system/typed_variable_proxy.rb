class TypedVariableProxy < BoxedVariable
  # [:!, :!=, :+, :==, :>, :<=, :>=, :*, :-, :<, :%, :/, :[], :[]=, :coerce, :length, :to_int, :to_str, :upcase, :cast, :push, :pop, :div, :downcase, :last].each do |method|
  #   undef_method(method) if method_defined?(method)
  # end
  
  def initialize(typed_variable)
    unless typed_variable.is_a?(::TypedVariable)
      raise "Can only use a TypedVariable: #{typed_variable.inspect}"
    end
    
    super(typed_variable)
  end

  def method_missing(name, *args, **kwargs, &block)
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    if name == :verifyTypedDataSignature
      args = ::VM.deep_get_values(args)
      kwargs = ::VM.deep_get_values(kwargs)
    end
    
    @value.handle_call_from_proxy(name, *args, **kwargs)
  end
end
