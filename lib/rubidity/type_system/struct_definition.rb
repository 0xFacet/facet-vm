class StructDefinition
  # TODO: basic object-ify
  attr_reader :name, :fields

  def initialize(name, &block)
    @name = name
    @fields = {}.with_indifferent_access
    instance_eval(&block)
    @fields = VM.deep_unbox(@fields)
  end

  define_method(ConstsToSends.box_function_name) do |value|
    VM.box(value)
  end

  ::Type.value_types.each do |type|
    define_method(type) do |name|
      update_struct_definition(type, name)
    end
  end
  
  def update_struct_definition(type, name)
    type = ::Type.create(type)
    
    if @fields[name]
      raise "No shadowing: #{name} is already defined."
    end
    
    @fields[name] = { type: type, args: [] }
  end
  
  def ==(other)
    other.is_a?(StructDefinition) &&
      other.name == name &&
      other.fields == fields
  end
end
