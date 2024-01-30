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
  
  def duplicate
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
      @state_proxy = StateProxy.new(struct_definition&.fields || {})
      
      values = values.serialize if values.respond_to?(:serialize)
      
      values = values&.transform_values{|v| v.respond_to?(:serialize) ? v.serialize : v}
      
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
