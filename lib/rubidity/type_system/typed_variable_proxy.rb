class TypedVariableProxy < BoxedVariable
  # [:!, :!=, :+, :==, :>, :<=, :>=, :*, :-, :<, :%, :/, :[], :[]=, :coerce, :length, :to_int, :to_str, :upcase, :cast, :push, :pop, :div, :downcase, :last].each do |method|
  #   undef_method(method) if method_defined?(method)
  # end
  
  def self.get_typed_var_if_necessary(proxy_or_var)
    if proxy_or_var.is_a?(::TypedVariable)
      proxy_or_var
    else
      ::TypedVariableProxy.get_typed_variable(proxy_or_var)
    end
  end
  
  def self.get_typed_variable(proxy)
    if ::VM.call_is_a?(proxy, ::TypedVariable)
      return proxy
    end
    
    unless ::CleanRoomAdmin.call_is_a?(proxy, ::TypedVariableProxy)
      raise "Can only use a proxy: #{proxy.inspect}"
    end
    
    var = ::CleanRoomAdmin.get_instance_variable(proxy, :value)
    
    unless ::VM.call_is_a?(var, ::TypedVariable)
      # binding.pry
      raise "Invalid typed variable in proxy: #{var.inspect}"
    end
    
    var
  end
  
  # TODO: Kill
  def cast(type)
    @value.cast(::VM.deep_unbox(type))
  end
  
  def to_ary
    raise unless @value.class == ::DestructureOnly
    @value.to_ary
  end
  
  def self.get_type(proxy)
    ::TypedVariableProxy.get_typed_variable(proxy).type
  end
  
  def initialize(typed_variable)
    unless ::VM.call_is_a?(typed_variable, ::TypedVariable) || ::VM.call_is_a?(typed_variable, ::DestructureOnly)
      raise "Can only use a TypedVariable: #{typed_variable.inspect}"
    end
    
    super(typed_variable)
  end

  def toPackedBytes
    @value.toPackedBytes
  end
  
  def as_json
    # TODO: remove this and stop ContractCall from coercing args to json. Have working_args or something.
    @value.as_json
  end
  
  def method_missing(name, *args, **kwargs, &block)
    klasses = [@value.class.ancestors - ::TypedVariable.ancestors]
    
    methods = klasses.flatten.flat_map do |klass|
      klass.instance_methods(false)
    end + @value.singleton_methods
    
    unless methods.include?(name)
      ::Kernel.instance_method(:raise).bind(self).call(::ContractErrors::VariableTypeError, "No method #{name} on #{@value.inspect}")
    end
    
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    if name == :verifyTypedDataSignature
      args = ::VM.deep_get_values(args)
      kwargs = ::VM.deep_get_values(kwargs)
    end
    
    res = if args.present? && kwargs.present?
      @value.public_send(name, *args, **kwargs)
    elsif args.present?
      @value.public_send(name, *args)
    else
      @value.public_send(name, **kwargs)
    end
    
    res
  end
end

