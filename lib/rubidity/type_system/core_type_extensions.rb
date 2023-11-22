module CoreTypeExtensions
  module Castable
    def cast(type)
      TypedVariable.create(type, self)
    end
  end
  
  module Etherable
    def ether
      (self.to_d * 1e18.to_d).to_i
    end
  end
  
  module BooleanExtensions
    include TypedObject
  
    def type
      Type.new(:bool)
    end
    
    def value=(*)
      raise TypeError.new("Cannot change value of #{self}")
    end
    
    def deserialize(*)
      raise TypeError.new("Cannot deserialize #{self}")
    end
  end
  
  ::String.include Castable
  
  ::Integer.include Castable
  ::Integer.include Etherable
  
  ::Float.include Etherable
  
  ::FalseClass.include BooleanExtensions
  ::TrueClass.include BooleanExtensions
end
