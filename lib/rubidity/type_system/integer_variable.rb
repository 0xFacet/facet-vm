class IntegerVariable < GenericVariable
  expose :ether, :days, :toString, :eq
  
  delegate :is_uint?, :is_int?, to: :type
  
  def initialize(...)
    super(...)
  end
  
  [:+, :-, :*, :/, :%, :**, :div].each do |operator|
    define_method(operator) do |other|
      perform_operation(other, operator)
    end
    
    expose operator
  end

  [:>, :<, :>=, :<=].each do |operator|
    operator_to_method_name = {
      :> => :gt,
      :<= => :lte,
      :>= => :gte,
      :< => :lt,
    }
    
    define_method(operator_to_method_name[operator]) do |other|
      perform_comparison(other, operator)
    end
    
    expose operator_to_method_name[operator]
  end
  
  def ether
    eth = (value.to_d * 1e18.to_d).to_i
    TypedVariable.create(:uint256, eth)
  end
  
  def days
    TypedVariable.create(:uint256, self.value.days)
  end
  
  def toString
    TypedVariable.create(:string, self.value.to_s)
  end
  
  def eq(other)
    enforce_typing!(other, :eq)

    TypedVariable.create(:bool, self.value == other.value)
  end
  
  def toPackedBytes
    bit_length = type.extract_integer_bits
    
    hex = (value % 2 ** bit_length).to_s(16)
    result = hex.rjust(bit_length / 4, '0')
    
    TypedVariable.create(:bytes, "0x" + result)
  end
  
  private
  
  def perform_operation(other, operation)
    enforce_typing!(other, operation)
    
    result = self.value.public_send(operation, other.value)
    TypedVariable.create(smallest_allowable_type(result), result)
  end

  def perform_comparison(other, operation)
    enforce_typing!(other, operation)
    
    TypedVariable.create(:bool, self.value.public_send(operation, other.value))
  end
  
  def enforce_typing!(other, operation)
    unless other.is_a?(IntegerVariable)
      raise ContractError.new("Comparison #{operation} not allowed between #{self.class} and #{other.class}")
    end
    
    # TODO: Nail down these rules
    
    # unless is_uint? && other.is_uint? || is_int? && other.is_int?
    #   raise ContractError.new("Comparison #{operation} not allowed between #{self.type} and #{other.type}")
    # end
  end
  
  delegate :smallest_allowable_type, to: :class
  def self.smallest_allowable_type(val)
    bits = val.bit_length + (val < 0 ? 1 : 0)
    whole_bits = bits / 8
    if bits % 8 != 0
      whole_bits += 1
    end
    
    whole_bits = 1 if whole_bits == 0
    
    type_prefix = val < 0 ? "int" : "uint"

    Type.create(:"#{type_prefix}#{whole_bits * 8}")
  end
end
