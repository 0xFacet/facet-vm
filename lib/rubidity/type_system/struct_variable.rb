class StructVariable < TypedVariable
  attr_accessor :value
  
  def initialize(type, value, **options)
    super(type, value, **options)
    
    self.value = Value.new(
      struct_definition: type.struct_definition,
      values: value,
      on_change: on_change
    )
  end
  
  def deep_dup
    fresh_type = Type.create(:struct, struct_definition: type.struct_definition)
    StructVariable.new(fresh_type, value.serialize, on_change: on_change)
  end
  
  def serialize
    value.state_proxy.serialize
  end
  
  def deserialize(hash)
    self.value = Value.new(
      struct_definition: type.struct_definition,
      values: hash,
      on_change: on_change
    )
  end
  
  def toPackedBytes
    res = value.state_proxy.state_variables.values
    .map do |val|
      val.toPackedBytes.value.sub(/\A0x/, '')
    end.join
    
    ::TypedVariable.create(:bytes, "0x" + res)
  end
  
  def method_missing(...)
    value.send(...)
  end
  
  def respond_to_missing?(name, include_private = false)
    value.respond_to?(name, include_private) || super
  end
  
  class Value
    include ContractErrors
    
    extend AttrPublicReadPrivateWrite
    
    attr_accessor :on_change
    attr_public_read_private_write :struct_definition, :state_proxy
    
    def initialize(
      struct_definition:,
      values:,
      on_change: nil
    )
      @struct_definition = struct_definition
      
      defined_fields = struct_definition&.fields || {}
      
      @state_proxy = StateProxy.new(defined_fields)
      
      values = values.serialize if values.respond_to?(:serialize)
      
      values = values&.transform_values{|v| v.respond_to?(:serialize) ? v.serialize : v}
      
      if values.present?
        unless defined_fields.keys.sort.map(&:to_s) == values.keys.sort.map(&:to_s)
          raise ArgumentError, "Keys of values hash must match fields of struct_definition. Got: #{values.keys.sort}, expected: #{defined_fields.keys.sort}"
        end
      end
      
      @state_proxy.deserialize(values || {})
      
      self.on_change = on_change
    end

    def method_missing(...)
      ret_val = nil
      
      begin
        state_proxy.detecting_changes(revert_on_change: true) do
          ret_val = state_proxy.send(...)
        end
      rescue InvalidStateVariableChange
        on_change&.call
      end
      
      ret_val
    end

    def respond_to_missing?(method_name, include_private = false)
      state_proxy.respond_to?(method_name, include_private) || super
    end
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.struct_definition == struct_definition &&
      other.serialize == serialize
    end
  end
end
