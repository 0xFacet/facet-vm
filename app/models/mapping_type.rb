class MappingType < TypedVariable
  def initialize(...)
    super(...)
    value.on_change = on_change
  end
  
  def serialize
    value.serialize
  end
  
  class Proxy
    extend AttrPublicReadPrivateWrite
    
    attr_accessor :on_change
    attr_public_read_private_write :transformed_keys, :data, :key_type, :value_type
    
    def serialize
      serialized_dirty_data = {}
      
      transformed_keys.each do |key|
        value = data[key]
        
        unless value.value == value.type.default_value
          serialized_dirty_data[key.serialize.to_s] = value.serialize
        end
      end
      
      clean_data = data.except(*transformed_keys)
      clean_data.merge(serialized_dirty_data).deep_dup
    end
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.key_type == key_type &&
      other.value_type == value_type &&
      other.serialize == serialize
    end
    
    def initialize(initial_value = {}, key_type:, value_type:, on_change: nil)
      self.key_type = key_type
      self.value_type = value_type
      
      self.data = initial_value
      self.transformed_keys = Set.new
      self.on_change = on_change
    end
    
    def [](key_var)
      raw_key = key_var.is_a?(TypedVariable) ? key_var.value : key_var
      string_key = raw_key.to_s
    
      typed_key_var = TypedVariable.create_or_validate(key_type, key_var, on_change: on_change)
    
      # First, attempt a lookup using the typed key
      value = data[typed_key_var]
    
      # If no value is found, try looking it up as a string (how it would be stored in JSONB)
      if value.nil? && data.key?(string_key)
        value = TypedVariable.create_or_validate(value_type, data[string_key], on_change: on_change)
        
        data.delete(string_key)
        set_value(typed_key_var, value)
      end
    
      # If the value is still nil, it truly doesn't exist; create a new default value
      if value.nil?
        value = TypedVariable.create_or_validate(value_type, on_change: on_change)
        set_value(typed_key_var, value)
      end
      
      value.deep_dup
    end

    def []=(key_var, value)
      key_var = TypedVariable.create_or_validate(key_type, key_var, on_change: on_change)
      val_var = TypedVariable.create_or_validate(value_type, value, on_change: on_change)

      if value_type.mapping?
        raise TypeError, "Mappings cannot be assigned to mappings"
      end
      
      old_value = self.data[key_var]
      
      if old_value != val_var
        on_change&.call
        
        transformed_keys.add(key_var)

        data[key_var] ||= val_var
        data[key_var].value = val_var.value
      end
    end
    
    private
    
    def set_value(key, value)
      data[key] = value
      transformed_keys.add(key)
    end
  end
end
