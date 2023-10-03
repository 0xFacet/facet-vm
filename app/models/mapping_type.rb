class MappingType < TypedVariable
  def initialize(type, value = nil, **options)
    super
  end
  def deep_clean(hash)
    hash.each_with_object({}) do |(k, v), new_hash|
      if v.is_a?(Hash)
        nested_hash = deep_clean(v)
        new_hash[k] = nested_hash unless nested_hash.empty?
      else
        new_hash[k] = v
      end
    end
  end
  def serialize(*)
    res = value.data_defaults_pruned.each.with_object({}) do |(key, value), h|
      # h[key.serialize] = value.serialize
      
      if value.respond_to?(:value)
        next if value.value == value.type.default_value
      end
      
      key = key.respond_to?(:serialize) ? key.serialize : key
      val = value.respond_to?(:serialize) ? value.serialize : value
      
      h[key] = val
    end
    
    deep_clean(res)
  end
  
  class Proxy
    attr_accessor :key_type, :value_type, :data
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.key_type == key_type &&
      other.value_type == value_type &&
      other.data_defaults_pruned == data_defaults_pruned
    end
    
    def data_defaults_pruned
      data#.reject { |key, value| value.value == value.type.default_value }
    end
    
    def initialize(initial_value = {}, key_type:, value_type:)
      self.key_type = key_type
      self.value_type = value_type
      
      self.data = initial_value
    end
    
    def [](key_var)
      key_var = TypedVariable.create_or_validate(key_type, key_var)
      value = data[key_var]

      if value.nil?
        data[key_var] = TypedVariable.create_or_validate(value_type, data.delete(key_var.value&.to_s))
      end
      
      data[key_var]
    end

    def []=(key_var, value)
      key_var = TypedVariable.create_or_validate(key_type, key_var)
      val_var = TypedVariable.create_or_validate(value_type, value)

      if value_type.mapping?
        val_var = Proxy.new(key_type: value_type.key_type, value_type: value_type.value_type)
        raise "What?"
      end

      self.data[key_var] ||= val_var
      self.data[key_var].value = val_var.value
    end
  end
end
