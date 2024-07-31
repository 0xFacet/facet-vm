class StructVariable < GenericVariable
  include Exposable
  
  attr_accessor :value
  
  def initialize(type, val, **options)
    super(type, val, **options)
    
    self.value = if val.is_a?(Value)
      val
    else
      Value.new(
        struct_definition: type.struct_definition,
        values: val,
      )
    end
  end
  
  def handle_call_from_proxy(method_name, *args, **kwargs)
    if method_exposed?(method_name)
      return super
    end
    
    chomped_method_name = method_name.to_s.chomp("=").to_sym
    
    unless value.struct_definition.fields.key?(chomped_method_name)
      raise NoMethodError, "Undefined method `#{method_name}` for #{self}"
    end
    
    if method_name.to_s.end_with?("=")
      value.set(chomped_method_name, args.first)
    else
      value.get(chomped_method_name)
    end
  end
  
  def as_json
    value.as_json
  end
  
  def serialize
    value.serialize
  end
  
  def eq(other)
    self.value == other.value
  end
  wrap_with_logging :eq
  
  def ne(other)
    !eq(other)
  end
  wrap_with_logging :ne
  
  class Value
    include ContractErrors
    include Exposable
    
    attr_accessor :data, :struct_definition
    
    def initialize(struct_definition:, values:)
      @struct_definition = struct_definition
      @data = {}.with_indifferent_access
      
      values.each do |key, value|
        self.set(key, value)
      end
      
      if values.present?
        unless struct_definition.fields.keys.sort.map(&:to_s) == values.keys.sort.map(&:to_s)
          raise ArgumentError, "Keys of values hash must match fields of struct_definition. Got: #{values.keys.sort}, expected: #{defined_fields.keys.sort}"
        end
      end
    # rescue => e
    #   binding.pry
    end
    
    def get(field)
      type = struct_definition.fields[field]

      TypedVariable.create_or_validate(type, data[field])
    end
    wrap_with_logging :get
    
    def set(field, new_value)
      type = struct_definition.fields[field]
      
      data[field] = TypedVariable.create_or_validate(type, new_value)
    end
    wrap_with_logging :set
    
    def ==(other)
      return false unless other.is_a?(self.class)
      
      other.struct_definition == struct_definition &&
      other.serialize == serialize
    end
    
    def toPackedBytes
      res = data.values
      .map do |val|
        val.toPackedBytes.value.sub(/\A0x/, '')
      end.join
      
      ::TypedVariable.create(:bytes, "0x" + res)
    end
    
    def as_json
      output = {}
      struct_definition.fields.each_key.each do |field|
        type = struct_definition.fields[field]
        value = data[field]
        
        output[field] = value || type.default_value
      end
      
      output.as_json
    end
    
    def serialize
      as_json
    end
  end
end
