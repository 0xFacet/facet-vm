class GenericVariable < TypedVariable
  include DefineMethodHelper
  include InstrumentAllMethods
  include Exposable
  
  expose :cast, :not, :ne, :eq
  
  def handle_call_from_proxy(method_name, *args, **kwargs)
    unless method_exposed?(method_name)
      raise NoMethodError.new("undefined method `#{method_name}' for #{self.inspect}")
    end
      
    TransactionContext.log_call("TypedVariable", self.class.name, method_name) do
      TransactionContext.increment_gas("TypedVariable#{method_name.to_s.upcase_first}")
      
      public_send(method_name, *args, **kwargs)
    end
  end
  
  def initialize(...)
    super(...)
  end
  
  def cast(type)
    TypedVariable.create(type, self.value)
  end
  
  def !
    raise TypeError.new("Call not() instead of !")
  end
  
  def ==(a)
    raise TypeError.new("Call eq() instead of ==()")
  end
  
  def not
    unless type.bool?
      raise TypeError.new("Cannot negate #{self.inspect}")
    end
    
    TypedVariable.create(:bool, !value)
  end
  
  def ne(other)
    (self.eq(other)).not
  end
  
  def eq(other)
    # TODO: we should also require other.eq(self) to be true
    
    if other.type.null?
      return TypedVariable.create(:bool, false)
    end
    
    unless other.is_a?(TypedVariable)
      raise ContractError.new("Cannot compare TypedVariable with #{other.class}")
    end
    
    unless type.values_can_be_compared?(other.type)
      raise ContractError.new("Cannot compare #{type.name} with #{other.type.name}")
    end
    
    TypedVariable.create(:bool, value == other.value)
  end
  
  def toPackedBytes
    if type.bool?
      bytes = value ? "0x01" : "0x00"
      return TypedVariable.create(:bytes, bytes)
    end
    
    TypedVariable.create(:bytes, value)
  end
end
