class ArrayType < TypedVariable
  def initialize(...)
    super(...)
    value.on_change = on_change
  end
  
  def serialize
    value.data.map(&:serialize)
  end
  
  class Proxy
    extend AttrPublicReadPrivateWrite
    
    attr_accessor :on_change
    attr_public_read_private_write :value_type, :data
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.value_type == value_type &&
      other.data == data
    end
  
    def initialize(
      initial_value = [],
      value_type:,
      initial_length: nil,
      on_change: nil
    )
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
      
      self.on_change = on_change
    end
  
    def [](index)
      index_var = TypedVariable.create_or_validate(:uint256, index, on_change: on_change)
      
      raise "Index out of bounds" if index_var >= data.size

      value = data[index_var]
      value.deep_dup || TypedVariable.create_or_validate(value_type, on_change: on_change)
    end
  
    def []=(index, value)
      index_var = TypedVariable.create_or_validate(:uint256, index, on_change: on_change)
      
      raise "Sparse arrays are not supported" if index_var > data.size

      old_value = self.data[index_var]
      val_var = TypedVariable.create_or_validate(value_type, value, on_change: on_change)
      
      if old_value != val_var
        on_change&.call
        
        if data[index_var].nil? || val_var.type.is_value_type?
          data[index_var] = val_var
        else
          data[index_var].value = val_var.value
        end
      end
    end
    
    def push(value)
      next_index = data.size
      
      self.[]=(next_index, value)
      nil
    end
    
    def pop
      on_change&.call
      
      data.pop
    end
    
    def length
      data.length
    end
    
    def last
      self.[](data.length - 1)
    end
  end
end
