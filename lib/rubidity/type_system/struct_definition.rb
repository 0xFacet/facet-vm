class StructDefinition
  attr_reader :name, :fields

  def initialize(name, &block)
    @name = name
    @fields = {}
    instance_eval(&block)
  end

  ::Type.value_types.each do |type|
    define_method(type) do |*args|
      update_struct_definition(type, args)
    end
  end
  
  def update_struct_definition(type, args)
    name = args.last.to_sym
    type = ::Type.create(type)
    
    if @fields[name]
      raise "No shadowing: #{name} is already defined."
    end
    
    @fields[name] = { type: type, args: args }
  end
end
