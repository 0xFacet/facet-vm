class FunctionContext < UltraBasicObject
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
    [:string, :address, :bytes32] +
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
    ]
    
    @allowed_contract_calls = @allowed_contract_calls.flatten.map(&:to_sym).to_set
  end

  def method_missing(name, *args, **kwargs, &block)
    if @args.members.include?(name.to_sym)
      @args[name.to_sym]
    elsif @allowed_contract_calls.include?(name.to_sym)
      # TODO: remove block unless forLoop
      ::Object.instance_method(:public_send).bind(@contract).call(name, *args, **kwargs, &block)
    else
      super
    end
  end
  
  # def respond_to_missing?(name, include_private = false)
  #   @args.respond_to?(name, include_private) || @contract.respond_to?(name, include_private)
  # end
  
  def self.define_and_call_function_method(contract, args, &block)
    context = new(contract, args)
    
    dummy_name = "__temp_method_#{::SecureRandom.hex(16)}__"
    
    singleton_class = (class << context; self; end)
    singleton_class.send(:define_method, dummy_name, &block)
    
    result = ::Object.instance_method(:__send__).bind(context).call(dummy_name)
    
    singleton_class.send(:remove_method, dummy_name)
    
    result
  end
end
