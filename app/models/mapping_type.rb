class MappingType < TypedVariable
  def initialize(type, value = nil, **options)
    super
  end
  
  def serialize
    value.serialize
  end
  
  class Proxy
    attr_accessor :key_type, :value_type, :data, :dirty_keys
    
    def serialize
      serialized_dirty_data = {}
      
      dirty_keys.each do |key|
        value = data[key]
        
        unless value.value == value.type.default_value
          serialized_dirty_data[key.serialize.to_s] = value.serialize
        end
      end
      
      clean_data = data.except(*dirty_keys)
      merged_data = clean_data.merge(serialized_dirty_data)
      
      sorted_data = merged_data.sort_by { |key, _| [key.length, key] }.to_h
      
      sorted_data.deep_dup
    end
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.key_type == key_type &&
      other.value_type == value_type &&
      other.serialize == serialize
    end
    
    def initialize(initial_value = {}, key_type:, value_type:)
      self.key_type = key_type
      self.value_type = value_type
      
      self.data = initial_value
      self.dirty_keys = Set.new
    end
    
    def [](key_var)
      raw_key = key_var.is_a?(TypedVariable) ? key_var.value : key_var
      string_key = raw_key.to_s
    
      typed_key_var = TypedVariable.create_or_validate(key_type, key_var)
    
      # First, attempt a lookup using the typed key
      value = data[typed_key_var]
    
      # If no value is found, try looking it up as a string (how it would be stored in JSONB)
      if value.nil? && data.key?(string_key)
        value = TypedVariable.create_or_validate(value_type, data[string_key])
        
        data.delete(string_key)
        set_value(typed_key_var, value)
      end
    
      # If the value is still nil, it truly doesn't exist; create a new default value
      if value.nil?
        value = TypedVariable.create_or_validate(value_type)
        set_value(typed_key_var, value)
      end
      
      value
    end

    def []=(key_var, value)
      key_var = TypedVariable.create_or_validate(key_type, key_var)
      val_var = TypedVariable.create_or_validate(value_type, value)

      if value_type.mapping?
        raise TypeError, "Mappings cannot be assigned to mappings"
      end

      dirty_keys.add(key_var)

      data[key_var] ||= val_var
      data[key_var].value = val_var.value
    end
    
    private
    
    def set_value(key, value)
      data[key] = value
      dirty_keys.add(key)
    end
  end
end
