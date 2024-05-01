class FunctionContext #< UltraBasicObject
  def initialize(contract, args)
    @contract = contract
    @args = args
    
    klass = ::Object.instance_method(:class).bind(contract).call
    
    @allowed_contract_calls = []
    
    @allowed_contract_calls += klass.abi.data.keys + 
    klass.available_contracts.keys +
    klass.structs.keys +
    klass.parent_contracts.map(&:name) +
    (8..256).step(8).flat_map{|i| ["uint#{i}", "int#{i}"]} +
    [:string, :address, :bytes32, :bool] +
    %i[
      s
      msg
      tx
      block
      require
      abi
      blockhash
      keccak256
      create2_address
      forLoop
      new
      emit
      this
      sqrt
      json
      array
      null
      __facet_true__
    ]
    
    @allowed_contract_calls = @allowed_contract_calls.flatten.map(&:to_sym).to_set
  end

  def method_missing(name, *args, **kwargs, &block)
    args = args.map do |arg|
      next arg unless arg.is_a?(::TypedVariableProxy)
      
      begin
        ::TypedVariableProxy.get_typed_variable(arg)
      rescue => e
        binding.pry
        raise e
      end
    end
    
    result = if @args.members.include?(name.to_sym)
      @args[name.to_sym]
    elsif @allowed_contract_calls.include?(name.to_sym)
      # TODO: remove block unless forLoop
      ::Object.instance_method(:public_send).bind(@contract).call(name, *args, **kwargs, &block)
    else
      super
    end
    
    result = result.to_proxy if result.is_a?(::TypedVariable)
    
    # TODO: fix proxy objects like ERC20
    # unless result.is_a?(::TypedVariableProxy)
      # raise "Invalid result type: #{result.class}"
    # end
    
    result
  end
  # TODO: not necessary for basic object setup
  def require(...)
    method_missing(:require, ...)
  end
  
  def Kernel
    ::Kernel
  end
  
  def self.define_and_call_function_method(contract, args, method_name, &block)
    context = new(contract, args)
    
    dummy_name = "__#{method_name}__"
    
    singleton_class = (class << context; self; end)
    singleton_class.send(:define_method, dummy_name, &block)
    
    result = ::Object.instance_method(:__send__).bind(context).call(dummy_name)
    
    singleton_class.send(:remove_method, dummy_name)
    
    result
  end
end
