class FunctionContext < UltraBasicObject
  # TODO: not necessary for basic object setup
  # undef_method :hash, :require
  
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
    
    if @args.method_exposed?(method_name) && args.blank? && kwargs.blank? && block.blank?
      @args.public_send(method_name)
    elsif @contract.method_exposed?(method_name)
      if method_name != :forLoop && block.present?
        raise ::ContractError.new("Block passed to function call that is not a forLoop")
      end
      
      @contract.public_send(method_name, *args, **kwargs, &block)
    else
      super
    end
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
