class FunctionContext < BasicObject
  def initialize(contract, args)
    @contract = contract
    @args = args
  end

  def method_missing(name, *args, **kwargs, &block)
    if @args.respond_to?(name)
      @args.public_send(name, *args, **kwargs, &block)
    else
      ::Object.instance_method(:public_send).bind(@contract).call(name, *args, **kwargs, &block)
    end
  end
  
  def respond_to_missing?(name, include_private = false)
    @args.respond_to?(name, include_private) || @contract.respond_to?(name, include_private)
  end
  
  def self.define_and_call_function_method(contract, args, &block)
    context = new(contract, args)
    
    dummy_name = "__#{::SecureRandom.base64(32)}__"
    
    singleton_class = (class << context; self; end)
    singleton_class.send(:define_method, dummy_name, &block)
    
    context.__send__(dummy_name)
  end
end
