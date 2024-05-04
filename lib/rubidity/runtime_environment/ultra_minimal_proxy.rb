class UltraMinimalProxy# < UltraBasicObject
  # (instance_methods + private_instance_methods).each do |name|
  #   unless [:__send__, :initialize].include?(name)
  #     undef_method(name)
  #   end
  # end
  
  def initialize(target, valid_call_method)
    @target = target
    @valid_call_method = valid_call_method
  end

  define_method(ConstsToSends.box_function_name) do |value|
    VM.box(value)
  end
  
  define_method(ConstsToSends.unbox_and_get_bool_function_name) do |value|
    VM.unbox_and_get_bool(value)
  end
  
  def method_missing(name, *args, **kwargs, &block)
    valid_method = case @valid_call_method
    when ::Enumerable
      @valid_call_method.include?(name)
    when ::Proc
      @valid_call_method.call(name)
    end
    
    if name.starts_with?("__") && name.ends_with?("__")
      valid_method = false
    end
    args = VM.deep_unbox(args)
    kwargs = VM.deep_unbox(kwargs)
    
    if valid_method
      @target.public_send(name, *args, **kwargs, &block)
    else
      super
    end
  end
  
  def respond_to_missing?(name, include_private = false)
    @valid_call_method.call(name) || super
  end
end
