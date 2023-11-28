class Type
  include ContractErrors
  
  attr_accessor :name, :metadata, :key_type, :value_type, :initial_length
  
  INTEGER_TYPES = (8..256).step(8).flat_map do |num|
    ["uint#{num}", "int#{num}"]
   end.map(&:to_sym)
  
  TYPES = [:string, :mapping, :address, :bytes32, :contract,
           :bool, :array, :bytes] + INTEGER_TYPES
  
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
    if type_name.is_a?(Array)
      if type_name.length != 1
        raise TypeError.new("Invalid array type #{type_name.inspect}")
      end
      
      value_type = type_name.first
      
      if TYPES.exclude?(value_type)
        raise TypeError.new("Invalid type #{value_type.inspect}")
      end
      
      metadata = { value_type: value_type }
      type_name = :array
    end
    
    type_name = type_name.to_sym
    
    if TYPES.exclude?(type_name)
      raise TypeError.new("Invalid type #{type_name.inspect}")
    end
    
    self.name = type_name.to_sym
    self.metadata = metadata.deep_dup
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
    self.initial_length = metadata[:initial_length] if metadata[:initial_length]
  end
  
  def can_be_assigned_from?(other_type)
    return true if self == other_type

    if is_uint? && other_type.is_uint? || is_int? && other_type.is_int?
      return extract_integer_bits >= other_type.extract_integer_bits
    end
    
    if address? && other_type.contract?
      return true
    end

    false
  end
  
  def values_can_be_compared?(other_type)
    return true if can_be_assigned_from?(other_type)

    if is_uint? && other_type.is_uint? || is_int? && other_type.is_int?
      return true
    end
    false
  end
  
  def metadata
    (@metadata ||= {}).with_indifferent_access
  end
  
  def to_s
    name.to_s
  end
  
  def default_value
    val = case
    when is_int? || is_uint?
      0
    when address?
      "0x" + "0" * 40
    when bytes32?
      "0x" + "0" * 64
    when string? || bytes?
      ''
    when bool?
      false
    when mapping?
      MappingVariable::Value.new(key_type: key_type, value_type: value_type)
    when array?
      ArrayVariable::Value.new(value_type: value_type, initial_length: initial_length)
    when contract?
      ContractVariable::Value.new(contract_class: metadata[:interface], address: nil)
    else
      raise "Unknown default value for #{self.inspect}"
    end
    
    check_and_normalize_literal(val)
  end
  
  def raise_variable_type_error(literal)
    raise VariableTypeError.new("Invalid #{self}: #{literal.inspect}")
  end
  
  def parse_integer(literal)
    base = literal.start_with?("0x") ? 16 : 10
    
    begin
      Integer(literal, base)
    rescue ArgumentError => e
      raise_variable_type_error(literal)
    end
  end
  
  def check_and_normalize_literal(literal)
    if literal.is_a?(TypedVariable)
      raise VariableTypeError, "Only literals and TypedObjects can be passed to check_and_normalize_literal: #{literal.inspect}"
    end
    
    if address?
      if literal.is_a?(ContractVariable::Value)
        return literal.address
      end
      
      unless literal.is_a?(String) && literal.match?(/\A0x[a-f0-9]{40}\z/i)
        raise_variable_type_error(literal)
      end
      
      return literal.downcase
    elsif is_uint?
      if literal.is_a?(String)
        literal = parse_integer(literal)
      end
        
      if literal.is_a?(Integer) && literal.between?(0, 2 ** extract_integer_bits - 1)
        return literal
      end
      
      raise_variable_type_error(literal)
    elsif is_int?
      if literal.is_a?(String)
        literal = parse_integer(literal)
      end
      
      if literal.is_a?(Integer) && literal.between?(-2 ** (extract_integer_bits - 1), 2 ** (extract_integer_bits - 1) - 1)
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
    elsif bytes32?
      unless literal.is_a?(String) && literal.match?(/\A0x[a-f0-9]{64}\z/i)
        raise_variable_type_error(literal)
      end
      
      return literal.downcase
    elsif bytes?
      if literal.is_a?(String) && literal.length == 0
        return literal
      end
      
      unless literal.is_a?(String) && literal.match?(/\A0x[a-fA-F0-9]+\z/) && literal.size.even?
        raise_variable_type_error(literal)
      end
      
      return literal.downcase
    elsif mapping?
      if literal.is_a?(MappingVariable::Value)
        return literal
      end
      
      unless literal.is_a?(Hash)
        raise VariableTypeError.new("invalid #{literal}")
      end
    
      proxy = MappingVariable::Value.new(literal, key_type: key_type, value_type: value_type)
      
      return proxy
    elsif array?
      if literal.is_a?(ArrayVariable::Value)
        return literal
      end
      
      unless literal.is_a?(Array)
        raise_variable_type_error(literal)
      end
      
      data = literal.map do |value|
        TypedVariable.create(value_type, value)
      end
    
      proxy = ArrayVariable::Value.new(data, value_type: value_type, initial_length: initial_length)
      
      return proxy
    elsif contract?
      if literal.is_a?(ContractVariable::Value)
        return literal
      else
        raise_variable_type_error("No literals allowed for contract types")
      end
    end
    
    raise VariableTypeError.new("Unknown type #{self.inspect}: #{literal.inspect}")
  end
  
  def is_uint?
    name.to_s.start_with?('uint')
  end

  def is_int?
    name.to_s.start_with?('int')
  end
  
  def extract_integer_bits
    return name.to_s[4..-1].to_i if is_uint?
    return name.to_s[3..-1].to_i if is_int?
    raise "Not an integer type: #{self}"
  end
  
  def ==(other)
    other.is_a?(self.class) &&
    other.name == name &&
    other.metadata.except(:initial_length) == metadata.except(:initial_length)
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