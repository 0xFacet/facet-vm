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
  
  define_method(ConstsToSends.box_function_name) do |value|
    VM.box(value)
  end
  
  define_method(ConstsToSends.unbox_and_get_bool_function_name) do |value|
    VM.unbox_and_get_bool(value)
  end
  
  def method_missing(method_name, *args, **kwargs, &block)
    get_values_for = [:contract, :pragma] + [
      :event,
      :function,
      :constructor,
      *::StateVariableDefinitions.public_instance_methods
    ]
    
    if get_values_for.include?(method_name)
      args = VM.deep_get_values(args)
      kwargs = VM.deep_get_values(kwargs)
    else
      args = VM.deep_unbox(args)
      kwargs = VM.deep_unbox(kwargs)
    end
    
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
