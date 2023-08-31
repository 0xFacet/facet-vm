class Type
  include ContractErrors
  
  attr_accessor :name, :metadata, :key_type, :value_type
  
  TYPES = [:string, :mapping, :address, :dumbContract,
          :addressOrDumbContract, :ethscriptionId,
          :bool, :address, :uint256, :int256, :array, :datetime]
  
  TYPES.each do |type|
    define_method("#{type}?") do
      self.name == type
    end
  end
  
  def self.value_types
    TYPES.select do |type|
      create(type).is_value_type?
    end
  end
  
  def initialize(type_name, metadata = {})
    type_name = type_name.to_sym
    
    if TYPES.exclude?(type_name)
      raise "Invalid type #{type_name}"
    end
    
    self.name = type_name.to_sym
    self.metadata = metadata
  end
  
  def self.create(type_or_name, metadata = {})
    return type_or_name if type_or_name.is_a?(self)
    
    new(type_or_name, metadata)
  end
  
  def key_type=(type)
    return if type.nil?
    @key_type = self.class.create(type)
  end
  
  def value_type=(type)
    return if type.nil?
    @value_type = self.class.create(type)
  end
  
  def metadata=(metadata)
    self.key_type = metadata[:key_type]
    self.value_type = metadata[:value_type]
  end
  
  def metadata
    { key_type: key_type, value_type: value_type }
  end
  
  def to_s
    name.to_s
  end
  
  def default_value
    is_int256_uint256_datetime = int256? || uint256? || datetime?
    is_addressOrDumbContract = address? || addressOrDumbContract?
    is_dumbContract_ethscriptionId = dumbContract? || ethscriptionId?
  
    val = case
    when is_int256_uint256_datetime
      0
    when is_addressOrDumbContract
      "0x" + "0" * 40
    when is_dumbContract_ethscriptionId
      "0x" + "0" * 64
    when string?
      ''
    when bool?
      false
    when mapping?
      MappingType::Proxy.new(key_type: key_type, value_type: value_type)
    when array?
      ArrayType::Proxy.new(value_type: value_type)
    else
      raise "Unknown default value for #{self.inspect}"
    end
    
    check_and_normalize_literal(val)
  end
  
  def raise_variable_type_error(literal)
    raise VariableTypeError.new("Invalid #{self}: #{literal.inspect}")
  end
  
  def check_and_normalize_literal(literal)
    if address?
      unless literal.is_a?(String) && literal.match?(/^0x[a-f0-9]{40}$/i)
        raise_variable_type_error(literal)
      end
      
      return literal.downcase
    elsif uint256?
      if literal.is_a?(String)
        begin
          literal = Integer(literal)
        rescue ArgumentError => e
          raise_variable_type_error(literal)
        end
      end
        
      if literal.is_a?(Integer) && literal.between?(0, 2 ** 256 - 1)
        return literal
      end
      
      raise_variable_type_error(literal)
    elsif int256?
      if literal.is_a?(String)
        begin
          literal = Integer(literal)
        rescue ArgumentError => e
          raise_variable_type_error(literal)
        end
      end
        
      if literal.is_a?(Integer) && literal.between?(-2 ** 255, 2 ** 255 - 1)
        return literal
      end
      
      raise_variable_type_error(literal)
    elsif string?
      unless literal.is_a?(String)
        raise_variable_type_error(literal)
      end
      
      return literal.freeze
    elsif bool?
      unless literal == true || literal == false
        raise_variable_type_error(literal)
      end
      
      return literal
    elsif (dumbContract? || ethscriptionId?)
      unless literal.is_a?(String) && literal.match?(/^0x[a-f0-9]{64}$/i)
        raise_variable_type_error(literal)
      end
      
      return literal.downcase
    elsif addressOrDumbContract?
      unless literal.is_a?(String) && (literal.match?(/^0x[a-f0-9]{64}$/i) || literal.match?(/^0x[a-f0-9]{40}$/i))
        raise_variable_type_error(literal)
      end
      
      return literal.downcase
    elsif datetime?
      dummy_uint = Type.create(:uint256)
      
      begin
        return dummy_uint.check_and_normalize_literal(literal)
      rescue VariableTypeError => e
        raise_variable_type_error(literal)
      end
    elsif mapping?
      if literal.is_a?(MappingType::Proxy)
        return literal
      end
      
      unless literal.is_a?(Hash)
        raise VariableTypeError.new("invalid #{literal}")
      end
      
      data = literal.map do |key, value|
        [
          TypedVariable.create(key_type, key),
          TypedVariable.create(value_type, value)
        ]
      end.to_h
    
      proxy = MappingType::Proxy.new(data, key_type: key_type, value_type: value_type)
      
      return proxy
    elsif array?
      if literal.is_a?(ArrayType::Proxy)
        return literal
      end
      
      unless literal.is_a?(Array)
        raise_variable_type_error(literal)
      end
      
      data = literal.map do |value|
        TypedVariable.create(value_type, value)
      end
    
      proxy = ArrayType::Proxy.new(data, value_type: value_type)
      
      return proxy
    end
    
    raise VariableTypeError.new("Unknown type #{self.inspect}: #{literal.inspect}")
  end
  
  def ==(other)
    other.is_a?(self.class) &&
    other.name == name &&
    other.metadata == metadata
  end
  
  def !=(other)
    !(self == other)
  end
  
  def hash
    [name, metadata].hash
  end

  def eql?(other)
    hash == other.hash
  end
  
  def is_value_type?
    !mapping? && !array?
  end
end