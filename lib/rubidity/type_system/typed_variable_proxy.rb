class TypedVariableProxy < BoxedVariable
  # [:!, :!=, :+, :==, :>, :<=, :>=, :*, :-, :<, :%, :/, :[], :[]=, :coerce, :length, :to_int, :to_str, :upcase, :cast, :push, :pop, :div, :downcase, :last].each do |method|
  #   undef_method(method) if method_defined?(method)
  # end
  
  def initialize(typed_variable)
    unless ::VM.call_is_a?(typed_variable, ::TypedVariable)
      raise "Can only use a TypedVariable: #{typed_variable.inspect}"
    end
    
    super(typed_variable)
  end

  def method_missing(name, *args, **kwargs, &block)
    unless @value.method_exposed?(name)
      ::Kernel.instance_method(:raise).bind(self).call(::ContractErrors::VariableTypeError, "No method #{name} on #{@value.inspect}")
    end
    
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    if name == :verifyTypedDataSignature
      args = ::VM.deep_get_values(args)
      kwargs = ::VM.deep_get_values(kwargs)
    end
    
    @value.public_send(name, *args, **kwargs)
  end
end
