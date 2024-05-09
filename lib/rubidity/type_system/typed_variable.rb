class TypedVariable
  include TypedObject
  
  include ContractErrors
  extend AttrPublicReadPrivateWrite
  extend Memoist
  class << self; extend Memoist; end
  
  [:==, :>, :<=, :>=, :<, :!, :!=].each do |method|
    undef_method(method) if method_defined?(method)
  end
  
  attr_accessor :value, :on_change
  attr_public_read_private_write :type
  # TODO: kill
  def to_proxy
    TypedVariableProxy.new(self)
  end
  
  def initialize(type, value = nil, on_change: nil, **options)
    self.type = type
    self.value = value.nil? ? type.default_value : value
    self.on_change = on_change
  end
  
  def self.create(type, value = nil, on_change: nil, **options)
    type = Type.create(type)
    
    options[:on_change] = on_change
    
    if type.mapping?
      MappingVariable.new(type, value, **options)
    elsif type.array?
      ArrayVariable.new(type, value, **options)
    elsif type.contract?
      ContractVariable.new(type, value, **options)
    elsif type.struct?
      StructVariable.new(type, value, **options)
    elsif type.string?
      StringVariable.new(type, value, **options)
    elsif type.is_int? || type.is_uint?
      IntegerVariable.new(type, value, **options)
    elsif type.null?
      NullVariable.instance
    else
      GenericVariable.new(type, value, **options)
    end
  end
  
  def self.create_as_proxy(...)
    ::TypedVariableProxy.new(create(...))
  end
  
  def self.create_or_validate(type, value = nil, on_change: nil)
    if CleanRoomAdmin.call_is_a?(value, TypedVariableProxy)
      value = CleanRoomAdmin.get_instance_variable(value, :value)
    end
    
    if value.is_a?(TypedObject)
      unless Type.create(type).can_be_assigned_from?(value.type)
        raise VariableTypeError.new("invalid #{type}: #{value.inspect}")
      end
      
      value = value.value
    end
    
    create(type, value, on_change: on_change)
  end
  
  def self.validated_value(type, value, allow_nil: false)
    if CleanRoomAdmin.call_is_a?(value, TypedVariableProxy)
      value = CleanRoomAdmin.get_instance_variable(value, :value)
    end
    
    return nil if value.nil? && allow_nil
    
    create_or_validate(type, value).value
  end
  
  def as_json(args = {})
    serialize
  end
  
  def to_s
    if type.string?
      value
    else
      raise "No string conversion"
    end
  end
  
  def value=(new_value)
    if type.bool? && !@value.nil?
      raise TypeError.new("Cannot change value of #{self.value.inspect}")
    end
    
    new_value = type.check_and_normalize_literal(new_value)
    
    if @value != new_value
      if type.is_value_type? && @value != type.default_value && !@value.nil?
        raise TypeError.new("Cannot change value of #{self.value.inspect}")
      end
      
      on_change&.call
      
      if new_value.respond_to?(:on_change=)
        new_value.on_change = on_change
      end
      
      @value = new_value
    end
  end
  
  def hash
    [value.hash, type.hash].hash
  end

  def eql?(other)
    hash == other.hash
  end
end
