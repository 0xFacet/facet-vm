class FunctionContext #< UltraBasicObject
  # TODO: not necessary for basic object setup
  undef_method :hash, :require
  
  def initialize(contract, method_name, args)
    @contract = contract
    @top_level_method_name = method_name
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
      memory
    ]
    
    @get_values_for = (8..256).step(8).flat_map{|i| ["uint#{i}", "int#{i}"]} + 
    %i[
      emit
      array
    ]
    
    @allowed_contract_calls = @allowed_contract_calls.flatten.map(&:to_sym).to_set
  end

  define_method(ConstsToSends.box_function_name) do |value|
    VM.box(value)
  end
  
  define_method(ConstsToSends.unbox_and_get_bool_function_name) do |value|
    VM.unbox_and_get_bool(value)
  end
  
  def method_missing(name, *args, **kwargs, &block)
    if @get_values_for.include?(name.to_sym)
      args = VM.deep_get_values(args)
      kwargs = VM.deep_get_values(kwargs)
    else
      args = VM.deep_unbox(args)
      kwargs = VM.deep_unbox(kwargs)
    end
    
    if @args.members.include?(name.to_sym)
      @args[name.to_sym]
    elsif @allowed_contract_calls.include?(name.to_sym)
      # TODO: remove block unless forLoop
      ::Object.instance_method(:public_send).bind(@contract).call(name, *args, **kwargs, &block)
    else
      super
    end
  end
  
  # TODO: remove
  def Kernel
    ::Kernel
  end
  
  def self.define_and_call_function_method(contract, args, method_name, &block)
    context = new(contract, method_name, args)
    
    dummy_name = "__#{method_name}__"
    
    singleton_class = (class << context; self; end)
    singleton_class.send(:define_method, dummy_name, &block)
    
    result = ::Object.instance_method(:__send__).bind(context).call(dummy_name)
    
    singleton_class.send(:remove_method, dummy_name)
    
    result
  end
end
