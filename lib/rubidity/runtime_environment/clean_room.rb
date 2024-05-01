class CleanRoom #< UltraBasicObject
  def initialize(context, valid_call_method)
    @context = context
    
    @wrapped_valid_call_method = ->(method_name) do
      if method_name.starts_with?("__") && method_name.ends_with?("__")
        next false
      end
      
      case valid_call_method
      when ::Enumerable
        valid_call_method.include?(method_name)
      when ::Proc
        valid_call_method.call(method_name)
      end
    end
  end

  def method_missing(method_name, *args, **kwargs, &block)
    if @wrapped_valid_call_method.call(method_name)
      ::Object.instance_method(:public_send).bind(@context).
        call(method_name, *args, **kwargs, &block)
    else
      super
    end
  rescue => e
    binding.pry
  end
  
  def self.execute_user_code_on_context(
    context,
    valid_call_method,
    method_name,
    user_code_or_block,
    filename = nil,
    line_number = nil
  )
    room = new(context, valid_call_method)
    
    dummy_name = "__#{method_name}__"
    
    singleton_class = (class << room; self; end)
    
    if user_code_or_block.is_a?(::String)
      method_definition = "def #{dummy_name}; #{user_code_or_block}; end"
      
      singleton_class.class_eval(
        method_definition,
        filename,
        line_number
      )
    else
      singleton_class.send(:define_method, dummy_name, &user_code_or_block)
    end
    
    result = ::Object.instance_method(:__send__).bind(room).call(dummy_name)
    
    singleton_class.send(:remove_method, dummy_name)
    
    result
  end
end
