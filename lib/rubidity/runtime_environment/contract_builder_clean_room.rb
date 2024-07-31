class ContractBuilderCleanRoom < UltraBasicObject
  def initialize(context, valid_call_methods)
    @context = context
    @valid_call_methods = valid_call_methods
  end
  
  define_method(::ConstsToSends.box_function_name) do |value|
    ::VM.box(value)
  end
  
  define_method(::ConstsToSends.unbox_and_get_bool_function_name) do |value|
    ::VM.unbox_and_get_bool(value)
  end
  
  def method_missing(method_name, *args, **kwargs, &block)
    structs = ::VM.get_instance_variable(@context, :structs, false)
    
    valid_method = @valid_call_methods.include?(method_name) ||
      (structs && structs[method_name])
    
    args = ::VM.deep_get_values(args)
    kwargs = ::VM.deep_get_values(kwargs)
    
    if valid_method
      # @context.handle_call_from_proxy(method_name, *args, **kwargs, &block)
      @context.__send__(method_name, *args, **kwargs, &block)
    else
      super
    end
  end
  
  def self.execute_user_code_on_context(
    context,
    valid_call_method,
    method_name,
    user_code_or_block,
    filename = nil
  )
    room = new(context, valid_call_method)
    
    dummy_name = "__#{method_name}__"
    
    singleton_class = (class << room; self; end)
        
    if user_code_or_block.is_a?(::String)
      method_definition = "def #{dummy_name}; ::Kernel.binding; end"
      
      singleton_class.class_eval(method_definition)
      
      _binding = ::VM.send_method(room, dummy_name)
      
      ::Kernel.eval(user_code_or_block, _binding, filename, 1)
    else
      singleton_class.define_method(dummy_name, &user_code_or_block)
      
      ::VM.send_method(room, dummy_name)
    end
  end
end
