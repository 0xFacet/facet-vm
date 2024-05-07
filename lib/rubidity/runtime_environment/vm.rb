module VM
  class BasicProxy
    def initialize(value = nil)
      @value = value
    end
    
    def value
      @value
    end
    
    def method_missing(method_name, *args, &block)
      @value.public_send(method_name, *args, &block)
    end
  end
  
  extend self
  
  def box(val)
    boxed_val = case val
    when BoxedVariable, BasicProxy
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
    when TypedVariable
      val.to_proxy
    when Array
      BoxedVariable.new(val)
    when BasicProxy, Hash, Class, Proc # proc for lambdas in forLoop
      BoxedVariable.new(val)
    when Struct, DestructureOnly
      return val # For box(msg).value
    when Binding
      raise unless Rails.env.development? || Rails.env.test?
      return val
    when Type
      if [:mapping, :array].include?(val.name)
        BoxedVariable.new(val)
      else
        raise "Invalid Type value: #{val.inspect}"
      end
    else
      raise "Invalid value to box: #{val.inspect}"
    end
    
    loop do
      return boxed_val if boxed_val.is_a?(BoxedVariable)
      
      boxed_val = box(boxed_val)
    end
  end
  
  def deep_unbox(value)
    case value
    when Array
      value.map { |item| deep_unbox(item) }
    when Hash
      value.transform_keys do |key|
        new_key = VM.deep_unbox(key)
        
        if new_key.is_a?(TypedVariable) && [:symbol, :string].include?(new_key.type.name)
          new_key.value.to_sym
        else
          new_key
        end
      end.transform_values { |val| deep_unbox(val) }.deep_symbolize_keys # TODO: Do this better
    when BoxedVariable
      deep_unbox(value.unbox)
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
    unless boxed_typed_var.is_a?(BoxedVariable)
      raise "Invalid value: #{boxed_typed_var.inspect}"
    end
    
    val = deep_unbox(boxed_typed_var)
    
    unless val.is_a?(TypedVariable) && val.type.bool?
      raise "Invalid value: #{val.inspect}"
    end
    
    val.value
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
