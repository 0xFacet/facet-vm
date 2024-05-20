class StructDefinition
  include Exposable
  
  attr_reader :name, :fields

  def initialize(name, &block)
    @name = name
    @fields = {}.with_indifferent_access
    
    StructDefinitionCleanRoom.execute(self, &block)
    
    @fields = VM.deep_unbox(@fields)
  end
  
  Type.value_types.each do |type|
    define_method(type) do |name|
      update_struct_definition(type, name)
    end
    
    expose(type)
  end
  
  def update_struct_definition(type, name)
    type = Type.create(type)
    name = VM.deep_get_values(name)
    
    if @fields[name]
      raise "No shadowing: #{name} is already defined."
    end
    
    @fields[name] = type
  end
  
  def ==(other)
    other.is_a?(StructDefinition) &&
      other.name == name &&
      other.fields == fields
  end
end
