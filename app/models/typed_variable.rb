class TypedVariable
  include ContractErrors
  
  attr_accessor :type, :value

  def initialize(type, value = nil, **options)
    self.type = type
    self.value = value || type.default_value
  end
  
  def self.create(type, value = nil, **options)
    type = Type.create(type)
    
    if type.mapping?
      MappingType.new(type, value, **options)
    elsif type.array?
      ArrayType.new(type, value, **options)
    elsif type.contract?
      ContractType.new(type, value, **options)
    else
      new(type, value, **options)
    end
  end
  
  def self.create_or_validate(type, value = nil)
    if value.is_a?(TypedVariable)
      unless Type.create(type).can_be_assigned_from?(value.type)
        raise VariableTypeError.new("invalid #{type}: #{value.inspect}")
      end
      
      value = value.value
    end
    
    create(type, value)
  end
  
  def as_json(args = {})
    serialize
  end
  
  def serialize
    value
  end
  
  def to_s
    if value.is_a?(String) || value.is_a?(Integer)
      value.to_s
    else
      raise "No string conversion"
    end
  end
  
  def deserialize(serialized_value)
    self.value = serialized_value
  end
  
  def value=(new_value)
    @value = type.check_and_normalize_literal(new_value)
  end
  
  def method_missing(name, *args, &block)
    if value.respond_to?(name)
      result = value.send(name, *args, &block)
      
      if result.class == value.class
        begin
          result = type.check_and_normalize_literal(result)
        rescue ContractErrors::VariableTypeError => e
          if type.is_uint?
            result = TypedVariable.create(:uint256, result)
          else
            raise
          end
        end
      end
      
      result
      
      if name.to_s.end_with?("=") && !%w[>= <=].include?(name.to_s[-2..])
        self.value = result if type.is_value_type?
        self
      else
        result
      end
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    value.respond_to?(name, include_private) || super
  end
  
  def !=(other)
    !(self == other)
  end
  
  def ==(other)
    if other.is_a?(self.class)
      return false unless type.values_can_be_compared?(other.type)
      return value == other.value
    else
      return value == TypedVariable.create(type, other).value
    end
  end
  
  def hash
    [value, type].hash
  end

  def eql?(other)
    hash == other.hash
  end
end
