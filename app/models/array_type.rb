class ArrayType < TypedVariable
  def initialize(type, value = nil, **options)
    super
  end
  
  def serialize(*)
    value.data.map(&:serialize)
  end
  
  class Proxy
    attr_accessor :value_type, :data
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.value_type == value_type &&
      other.data == data
    end
  
    def initialize(initial_value = [], value_type:, initial_length: nil)
      unless value_type.is_value_type?
        raise VariableTypeError.new("Only value types can me array elements")
      end
      
      self.value_type = value_type
      self.data = initial_value
      
      if initial_length
        amount_to_pad = initial_length - data.size
        
        amount_to_pad.times do
          data << TypedVariable.create(value_type) 
        end
      end
    end
  
    def [](index)
      index_var = TypedVariable.create_or_validate(:uint256, index)
      
      raise "Index out of bounds" if index_var >= data.size

      value = data[index_var]
      value || TypedVariable.create_or_validate(value_type)
    end
  
    def []=(index, value)
      index_var = TypedVariable.create_or_validate(:uint256, index)
      
      raise "Sparse arrays are not supported" if index_var > data.size

      val_var = TypedVariable.create_or_validate(value_type, value)
      
      self.data[index_var] ||= val_var
      self.data[index_var].value = val_var.value
    end
    
    def push(value)
      next_index = data.size
      
      self.[]=(next_index, value)
      nil
    end
    
    def pop
      data.pop
    end
    
    def length
      data.length
    end
  end
end
