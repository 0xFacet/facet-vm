module VM
  extend self
  
  def box(val)
    boxed_val = case val
    when BoxedVariable
      return val
    when nil
      NullVariable.instance
    when true, false
      TypedVariable.create(:bool, val)
    when Integer
      TypedVariable.create(infer_int_type(val), val)
    when String
      TypedVariable.create(:string, val)
    when Symbol
      TypedVariable.create(:symbol, val)
    when StoragePointer
      StoragePointerProxy.new(val)
    when TypedVariable
      TypedVariableProxy.new(val)
    when Array, Hash, Proc, DestructureOnly # proc for lambdas in forLoop
      BoxedVariable.new(val)
    when Type
      BoxedVariable.new(val)
    when Binding, Kernel
      raise unless Rails.env.development? || Rails.env.test?
      return val
    else
      raise "Invalid value to box: #{val.inspect}"
    end
    
    loop do
      return boxed_val if call_is_a?(boxed_val, BoxedVariable)
      
      boxed_val = box(boxed_val)
    end
  end
  
  def unbox(i)
    deep_unbox(i)
  end
  
  def deep_unbox(value)
    case value
    when Array
      value.map { |item| deep_unbox(item) }
    when Hash
      value.transform_keys do |key|
        val = VM.deep_unbox(key)
        
        if val.is_a?(String)
          val.to_sym
        elsif val.is_a?(Symbol)
          val
        else
          raise "Invalid key type: #{val.inspect}"
        end
      end.transform_values { |val| deep_unbox(val) }
    when BoxedVariable
      deep_unbox(
        get_instance_variable(value, :value)
      )
    else
      value
    end
  end
  
  def deep_get_values(value)
    unboxed = deep_unbox(value)
    
    case unboxed
    when TypedVariable
      unboxed.serialize
    when Array
      unboxed.map { |item| deep_get_values(item) }
    when Hash
      unboxed.transform_keys { |key| deep_get_values(key) }
           .transform_values { |val| deep_get_values(val) }
    else
      unboxed
    end
  end
  
  def boxed?(value)
    value.is_a?(BoxedVariable)
  end
  
  def unbox_and_get_bool(boxed_typed_var)
    unless call_is_a?(boxed_typed_var, BoxedVariable)
      raise "Invalid value: #{boxed_typed_var.inspect}"
    end
    
    val = deep_unbox(boxed_typed_var)
    
    unless call_is_a?(val, TypedVariable) && val.type.bool?
      raise "Invalid value: #{val.inspect}"
    end
    
    val.value
  end
  
  def send_method(
    _binding,
    method_name,
    args: [],
    kwargs: {},
    &block
  )
    Object.instance_method(:__send__).
      bind_call(_binding, method_name, *args, **kwargs, &block)
  end
  
  def call_method(
    _binding,
    method_name,
    args: [],
    kwargs: {},
    &block
  )
    Object.instance_method(method_name).
      bind_call(_binding, *Array.wrap(args), **kwargs, &block)
  end
  
  def get_instance_variable(_binding, name, revert_if_undefined = true)
    unless name.starts_with?("@")
      name = "@#{name}"
    end
    
    defined = call_method(
      _binding,
      :instance_variable_defined?,
      args: name
    )
    
    if !defined && revert_if_undefined
      raise "Instance variable not defined: #{name}"
    end
    
    call_method(
      _binding,
      :instance_variable_get,
      args: name
    )
  end
  
  def call_respond_to?(_binding, name)
    call_method(
      _binding,
      :respond_to?,
      args: name
    )
  end
  
  def call_is_a?(_binding, name)
    call_method(
      _binding,
      :is_a?,
      args: name
    )
  end
  
  def get_singleton_class(_binding)
    call_method(
      _binding,
      :singleton_class
    )
  end
  
  private
  
  def infer_int_type(value)
    bits = value.bit_length + (value < 0 ? 1 : 0)
    whole_bits = bits / 8
    if bits % 8 != 0
      whole_bits += 1
    end
    
    whole_bits = 1 if whole_bits == 0
    
    type_prefix = value < 0 ? "int" : "uint"
    :"#{type_prefix}#{whole_bits * 8}"
  end
  
  def assert(condition, message = "Assertion failed")
    raise message unless condition
  end
end
