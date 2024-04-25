class UltraMinimalProxy < UltraBasicObject
  # (instance_methods + private_instance_methods).each do |method_name|
  #   unless [:__send__, :initialize].include?(method_name)
  #     undef_method(method_name)
  #   end
  # end
  
  def initialize(target, valid_call_method)
    @target = target
    @valid_call_method = valid_call_method
  end

  def method_missing(method_name, *args, **kwargs, &block)
    valid_method = case @valid_call_method
    when ::Enumerable
      @valid_call_method.include?(method_name)
    when ::Proc
      @valid_call_method.call(method_name)
    end
    
    if valid_method
      @target.public_send(method_name, *args, **kwargs, &block)
    else
      super
    end
  end
  
  # def respond_to_missing?(method_name, include_private = false)
  #   @valid_call_method.call(method_name) || super
  # end
end
