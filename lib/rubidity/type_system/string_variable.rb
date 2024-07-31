class StringVariable < GenericVariable
  expose :+, :[], :length, :upcase, :downcase, :base64Encode,
    :base64Decode, :isAlphaNumeric?
  
  def initialize(...)
    super(...)
  end
  
  # TODO: gas for methods that check every character should depend on string length
  
  def +(other)
    unless other.is_a?(StringVariable)
      raise ContractError.new("Cannot add #{self.class} to #{other.class}")
    end
    
    TypedVariable.create(:string, self.value + other.value)
  end
  
  def [](index)
    TypedVariable.create(:string, self.value[index.value])
  end
  
  def length
    TypedVariable.create(:uint256, self.value.length)
  end
  
  def upcase
    TypedVariable.create(:string, self.value.upcase)
  end
  
  def downcase
    TypedVariable.create(:string, self.value.downcase)
  end
  
  def base64Encode
    TypedVariable.create(:string, Base64.strict_encode64(value))
  end
  
  def base64Decode
    TypedVariable.create(:string, Base64.strict_decode64(value))
  end
  
  def isAlphaNumeric?
    TypedVariable.create(:bool, !!(value =~ /\A[a-z0-9]+\z/i))
  end
  
  def toPackedBytes
    TypedVariable.create(:bytes, "0x" + value.unpack1('H*'))
  end
end
