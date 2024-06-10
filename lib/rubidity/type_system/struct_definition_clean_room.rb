class StructDefinitionCleanRoom < UltraBasicObject
  def initialize(struct_definition)
    @struct_definition = struct_definition
  end
  
  define_method(::ConstsToSends.box_function_name) do |value|
    ::VM.box(value)
  end
  
  define_method(::ConstsToSends.unbox_and_get_bool_function_name) do |value|
    ::VM.unbox_and_get_bool(value)
  end
  
  def method_missing(method_name, *args, **kwargs)
    args = ::VM.deep_unbox(args)
    kwargs = ::VM.deep_unbox(kwargs)
    
    if @struct_definition.method_exposed?(method_name)
      @struct_definition.public_send(method_name, *args, **kwargs)
    else
      super
    end
  end
  
  def self.execute(struct_definition, &block)
    context = new(struct_definition)
    
    dummy_name = "__#{::SecureRandom.hex}__"
    
    singleton_class = (class << context; self; end)
    singleton_class.send(:define_method, dummy_name, &block)
    
    result = context.__send__(dummy_name)
    
    result
  end
end
