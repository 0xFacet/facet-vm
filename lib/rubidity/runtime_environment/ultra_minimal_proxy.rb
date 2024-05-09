class UltraMinimalProxy < UltraBasicObject
  def initialize(target, valid_methods)
    @target = target
    @valid_methods = valid_methods
  end

  define_method(::ConstsToSends.box_function_name) do |value|
    ::VM.box(value)
  end
  
  define_method(::ConstsToSends.unbox_and_get_bool_function_name) do |value|
    ::VM.unbox_and_get_bool(value)
  end
  
  def method_missing(name, *args, **kwargs, &block)
    if name.starts_with?("__") && name.ends_with?("__")
      valid_method = false
    end
    
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    if @valid_methods.include?(name)
      @target.public_send(name, *args, **kwargs, &block)
    else
      super
    end
  end
end
