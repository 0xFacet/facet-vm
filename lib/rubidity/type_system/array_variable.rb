class ArrayVariable < GenericVariable
  MAX_ARRAY_LENGTH = 100
  
  delegate :push, :pop, :length, :last, :[], :[]=, to: :value
  
  def initialize(...)
    super(...)
    value.on_change = -> { on_change&.call }
  end
  
  def serialize
    value.data.map(&:serialize)
  end
  
  def toPackedBytes
    res = value.data.map do |arg|
      bytes = arg.toPackedBytes
      bytes = bytes.value.sub(/\A0x/, '')
    end.join
    
    ::TypedVariable.create(:bytes, "0x" + res)
  end
  
  class Value
    extend AttrPublicReadPrivateWrite
    
    attr_accessor :on_change
    attr_public_read_private_write :value_type, :data
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.value_type == value_type &&
      data.length == other.data.length &&
      data.each.with_index.all? do |item, index|
        item.eq(other.data[index]).value
      end
    end
  
    def initialize(
      initial_value = [],
      value_type:,
      initial_length: nil,
      on_change: nil
    )
      if value_type.mapping? || value_type.array?
        raise VariableTypeError.new("Arrays of mappings or arrays are not supported")
      end
      
      self.value_type = value_type
      self.on_change = on_change
      self.data = initial_value

      if initial_length
        amount_to_pad = initial_length - data.size
        
        amount_to_pad.times do
          data << TypedVariable.create(value_type, on_change: -> { on_change&.call })
        end
      end
    end
  
    def [](index)
      index_var = TypedVariable.create_or_validate(:uint256, index, on_change: -> { on_change&.call })
      
      raise "Index out of bounds" if index_var.gte(length).value
      
      value = data[index_var.value] ||
        TypedVariable.create_or_validate(value_type, on_change: -> { on_change&.call })
      
      if value_type.is_value_type?
        value.deep_dup
      else
        value.on_change = -> { on_change&.call }
        value
      end
    end
  
    def []=(index, value)
      index_var = TypedVariable.create_or_validate(:uint256, index, on_change: -> { on_change&.call })
      raise "Sparse arrays are not supported" if index_var.gt(length).value
      max_len = TypedVariable.create(:uint256, MAX_ARRAY_LENGTH)
      raise "Max array length is #{MAX_ARRAY_LENGTH}" if index_var.gte(max_len).value

      val_var = TypedVariable.create_or_validate(value_type, value, on_change: -> { on_change&.call })
      
      if index_var.eq(length).value || self[index_var].ne(val_var).value
        on_change&.call
        
        if data[index_var.value].nil? || val_var.type.is_value_type?
          data[index_var.value] = val_var
        else
          data[index_var.value].value = val_var.value
        end
      end
      
      data[index_var.value]
    end
    
    def push(value)
      next_index = data.size
      
      self.[]=(next_index, value)
      NullVariable.instance
    end
    
    # TODO: In Solidity this returns null
    def pop
      on_change&.call
      
      TypedVariable.create(value_type, data.pop.value)
    end
    
    def length
      TypedVariable.create(:uint256, data.length)
    end
    
    def last
      self.[](data.length - 1)
    end
  end
end
