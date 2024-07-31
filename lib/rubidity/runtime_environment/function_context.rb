class FunctionContext < UltraBasicObject
  # TODO: not necessary for basic object setup
  # [:hash, :require, :p].each do |method_name|
  #   undef_method(method_name) if method_defined?(method_name)
  # end
  
  def initialize(contract, args)
    @contract = contract
    @args = args
  end
  
  define_method(::ConstsToSends.box_function_name) do |value|
    ::VM.box(value)
  end
  
  define_method(::ConstsToSends.unbox_and_get_bool_function_name) do |value|
    ::VM.unbox_and_get_bool(value)
  end
  
  def method_missing(method_name, *args, **kwargs, &block)
    if %i[emit array].include?(method_name)
      args = ::VM.deep_get_values(args)
      kwargs = ::VM.deep_get_values(kwargs)
    else
      args = ::VM.deep_unbox(args)
      kwargs = ::VM.deep_unbox(kwargs)
    end
    
    function_arg = @args.get_arg(method_name)
    
    function_arg ||
      @contract.handle_call_from_proxy(method_name, *args, **kwargs, &block)
  end
  
  # TODO: remove
  # def Kernel
  #   ::Kernel
  # end
  
  def self.define_and_call_function_method(contract, args, method_name, &block)
    context = new(contract, args)
    
    dummy_name = "__#{method_name}__"
    
    singleton_class = (class << context; self; end)
    singleton_class.send(:define_method, dummy_name, &block)
    
    result = ::Object.instance_method(:__send__).bind(context).call(dummy_name)
    
    result
  end
end
