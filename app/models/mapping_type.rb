class MappingType < TypedVariable
  def initialize(type, value = nil, **options)
    super
  end
  
  def serialize
    value.data.each.with_object({}) do |(key, value), h|
      h[key.serialize] = value.serialize
    end
  end
  
  class Proxy
    attr_accessor :key_type, :value_type, :data
    
    def initialize(initial_value = {}, key_type:, value_type:)
      self.key_type = key_type
      self.value_type = value_type
      
      self.data = initial_value
    end
    
    def [](key_var)
      key_var = TypedVariable.create_or_validate(key_type, key_var)
      value = data[key_var]

      if value_type.mapping? && value.nil?
        value = TypedVariable.create_or_validate(value_type)
        data[key_var] = value
      end

      value || TypedVariable.create_or_validate(value_type)
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
