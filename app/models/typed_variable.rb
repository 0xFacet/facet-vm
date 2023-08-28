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
    else
      new(type, value, **options)
    end
  end
  
  def as_json(args = {})
    serialize
  end
  
  def serialize
    value
  end
  
  def to_s
    value.is_a?(String) ? value : super
  end
  
  def deserialize(serialized_value)
    self.value = serialized_value
  end
  
  def value=(new_value)
    @value = if new_value.is_a?(TypedVariable)
      if new_value.type != type
        if type == Type.create(:addressOrDumbContract) &&
           [Type.create(:address), Type.create(:dumbContract)].include?(new_value.type)
           
          new_value.value
        else
          raise VariableTypeError.new("invalid #{type}: #{new_value.value}")
        end
      end
      
      new_value.value
    else
      type.check_and_normalize_literal(new_value)
    end
  end
  
  def method_missing(name, *args, &block)
    if value.respond_to?(name)
      result = value.send(name, *args, &block)
      
      if name.to_s.end_with?("=") && !%w[>= <=].include?(name.to_s[-2..])
        self.value = result if type.is_value_type?
        self
      else
        result
      end
    else
      binding.pry
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
    other.is_a?(self.class) &&
    value == other.value &&
    type == other.type
  end
  
  def hash
    [value, type].hash
  end

  def eql?(other)
    hash == other.hash
  end
end
