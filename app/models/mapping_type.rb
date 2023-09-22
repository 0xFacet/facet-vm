class MappingType < TypedVariable
  def initialize(type, value = nil, **options)
    super
  end
  
  def serialize
    value.data_defaults_pruned.each.with_object({}) do |(key, value), h|
      h[key.serialize] = value.serialize
    end
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
      data.reject { |key, value| value.value == value.type.default_value }
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
        data[key_var] = TypedVariable.create_or_validate(value_type)
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
