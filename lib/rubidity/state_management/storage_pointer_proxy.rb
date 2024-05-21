class StoragePointerProxy < BoxedVariable
  def initialize(pointer)
    super(pointer)
  end
  
  def method_missing(name, *args, **kwargs)
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    unless @value.method_exposed?(name)
      ::Kernel.raise ::ContractErrors::ContractError.new("Function #{name} not exposed in contract")
    end

    @value.public_send(name, *args, **kwargs)
  end
end
