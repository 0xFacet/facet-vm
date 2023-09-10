class FunctionContext < BasicObject
  include ::Kernel
  attr_reader :contract, :args
  
  def initialize(contract, args)
    @contract = contract
    @args = args
  end

  def method_missing(name, *args, **kwargs, &block)
    if @args.respond_to?(name)
      @args.send(name, *args, **kwargs, &block)
    else
      @contract.send(name, *args, **kwargs, &block)
    end
  end
  
  def require(*args)
    @contract.send(:require, *args)
  end
  
  def respond_to_missing?(name, include_private = false)
    @args.respond_to?(name, include_private) || @contract.respond_to?(name, include_private)
  end
  
  def self.define_and_call_function_method(contract, args, &block)
    context = new(contract, args)
    context.define_singleton_method(:function_implementation, &block)
    context.function_implementation
  end
end
