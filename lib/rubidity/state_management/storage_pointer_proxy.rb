class StoragePointerProxy < BoxedVariable
  def initialize(pointer)
    super(pointer)
  end
  
  def method_missing(name, *args, **kwargs)
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    @value.handle_call_from_proxy(name, *args, **kwargs)
  end
end
