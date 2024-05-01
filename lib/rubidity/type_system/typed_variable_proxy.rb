class TypedVariableProxy # < UltraBasicObject
  [:!, :!=, :+, :==, :>, :<=, :>=, :*, :-, :<, :%, :/, :[], :[]=, :coerce, :length, :to_int, :to_str, :upcase, :cast, :push, :pop, :div, :downcase, :last].each do |method|
    undef_method(method) if method_defined?(method)
  end
  
  def self.get_typed_var_if_necessary(proxy_or_var)
    if proxy_or_var.is_a?(::TypedVariable)
      proxy_or_var
    else
      ::TypedVariableProxy.get_typed_variable(proxy_or_var)
    end
  end
  
  def to_proxy
    self
  end
  
  def unwrap
    @typed_variable
  end
  
  def self.get_typed_variable(proxy)
    if proxy.is_a?(::TypedVariable)
      return proxy
    end
    
    unless ::CleanRoomAdmin.call_is_a?(proxy, TypedVariableProxy)
      raise "Can only use a proxy: #{proxy.inspect}"
    end
    
    var = ::CleanRoomAdmin.get_instance_variable(proxy, :typed_variable)
    
    unless var.is_a?(::TypedVariable)
      # binding.pry
      raise "Invalid typed variable in proxy: #{var.inspect}"
    end
    
    var
  end
  
  def cast(type)
    @typed_variable.cast(type).to_proxy
  end
  
  def to_ary
    raise unless @typed_variable.class == ::DestructureOnly
    @typed_variable.to_ary
  end
  
  def self.get_type(proxy)
    ::TypedVariableProxy.get_typed_variable(proxy).type
  end
  
  def initialize(typed_variable)
    unless typed_variable.nil? || typed_variable.is_a?(::TypedVariable) || typed_variable.is_a?(::DestructureOnly)
      raise "Can only use a TypedVariable: #{typed_variable.inspect}"
    end
    
    @typed_variable = typed_variable
  end

  def toPackedBytes
    @typed_variable.toPackedBytes
  end
  
  def as_json
    # TODO: remove this and stop ContractCall from coercing args to json. Have working_args or something.
    @typed_variable.as_json
  end
  
  def method_missing(name, *args, **kwargs, &block)
    klasses = [@typed_variable.class.ancestors - ::TypedVariable.ancestors]
    
    methods = klasses.flatten.flat_map do |klass|
      klass.instance_methods(false)
    end + @typed_variable.singleton_methods
    
    unless methods.include?(name)
      binding.pry
      raise "No method #{name} on #{@typed_variable.inspect}"
    end
    
    if name == :verifyTypedDataSignature
      res = @typed_variable.public_send(name, *args, **kwargs)
      return ::TypedVariableProxy.new(res)
    end
    
    args = args.map do |arg|
      begin
        ::TypedVariableProxy.get_typed_variable(arg)
      rescue => e
        binding.pry
        raise e
      end
    end
    
    res = if args.present? && kwargs.present?
      binding.pry
      @typed_variable.public_send(name, *args, **kwargs)
    elsif args.present?
      @typed_variable.public_send(name, *args)
    else
      @typed_variable.public_send(name, **kwargs)
    end
    
    if res.is_a?(::TypedVariable)
      res = ::TypedVariableProxy.new(res)
    end
    
    res
  end
end

