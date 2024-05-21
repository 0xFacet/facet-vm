# TODO: put behind save proxy
class StoragePointer
  attr_accessor :state_manager, :path
  
  def initialize(state_manager, path = [])
    @state_manager = state_manager
    @path = path
    
    # define_methods
  end

  def wrapper
    state_manager
  end
  
  def [](key)
    get(key)
  end

  def []=(key, value)
    set(key, value)
  end
  
  def method_missing(name, *args)
    name = name.to_s
    
    if name[-1] == '='
      key = name[0..-2]
      value = args.first
      set(key, value)
    else
      get(name)
    end
  end
  
  def respond_to_missing?(name, include_private = false)
    true
  end
  
  def load_array
    length.as_json.times.map do |index|
      self[TypedVariable.create(:uint256, index)].as_json
    end.deep_dup
  end
  
  def current_type
    @state_manager.validate_and_get_type(@path)
  end
  
  def load_struct
    struct_type = @state_manager.validate_and_get_type(@path)
    raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?

    data = struct_type.struct_definition.fields.keys.each_with_object({}) do |field, hash|
      hash[field] = self[field]
    end.deep_dup
    
    # value = StructVariable::Value.new(values: data, struct_definition: struct_type.struct_definition)
    
    StructVariable.new(struct_type, data)
  rescue => e
    binding.pry
  end
  
  def push(value)
    validate_array!
    value = VM.unbox(value)
    
    if value.is_a?(StoragePointer)
      type = @state_manager.validate_and_get_type(value.path)
      
      if type.struct?
        value = value.load_struct
      else
        raise TypeError, "Invalid type for StoragePointer assignment"
      end
    end
    
    @state_manager.array_push(*@path, value)
  end

  def pop
    validate_array!
    @state_manager.array_pop(*@path)
  end

  def length
    validate_array!
    @state_manager.array_length(*@path)
  end
  
  def last
    validate_array!
    self[self.length - TypedVariable.create(:uint256, 1)]
  end
  
  def as_json
    type = @state_manager.validate_and_get_type(@path)
    
    if type.array?
      load_array
    elsif type.struct?
      load_struct
    else
      raise
      @state_manager.get(*@path).as_json
    end.as_json
  end
  
  def validate_array!
    type = @state_manager.validate_and_get_type(@path)
    raise TypeError, "Cannot duplicate non-array type" unless type.name == :array
  end

  # TODO: Validate it's actually an array and the path is an array
  def set_array(new_array)
    # Pop all existing values
    while length.value > 0
      pop
    end

    # Push new values
    if new_array.is_a?(StoragePointer)
      new_array.length.value.times do |index|
        push(new_array[index])
      end
    else
      new_array.value.data.each do |element|
        push(element)
      end
    end
  end
  
  def eq(other)
    struct_type = @state_manager.validate_and_get_type(@path)
    raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?
    
    other = VM.unbox(other)
    
    load_struct.eq(other)
  # rescue => e
  #   binding.pry
  end
  
  def ne(other)
    struct_type = @state_manager.validate_and_get_type(@path)
    raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?
    
    other = VM.unbox(other)
    
    load_struct.ne(other)
  # rescue => e
  #   binding.pry
  end
  
  def set_struct(new_struct)
    struct_type = @state_manager.validate_and_get_type(@path)
    raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?

    struct_definition = struct_type.struct_definition
    
    other = VM.unbox(new_struct)
    
    # Set each field in the struct
    if new_struct.is_a?(StoragePointer)
      struct_definition.fields.keys.each do |field|
        self[field] = new_struct[field]
      end
    elsif new_struct.is_a?(StructVariable)
      struct_definition.fields.keys.each do |field|
        self[field] = new_struct.value.get(field)
      end
    else
      raise TypeError, "Expected a struct or StoragePointer, got #{new_struct.class}"
    end
  rescue => e
    binding.pry
  end
  
  private

  def set(key, value)
    key = VM.unbox(key)
    value = VM.unbox(value)
    
    new_path = @path + [key]
    
    type = @state_manager.validate_and_get_type(new_path)

    if type.name == :array && value.is_a?(ArrayVariable)
      StoragePointer.new(@state_manager, new_path).set_array(value)
    elsif type.struct?
      StoragePointer.new(@state_manager, new_path).set_struct(value)
    elsif value.is_a?(StoragePointer)
      if type.name == :array
        set_array(value)
      elsif type.struct?
        set_struct(value)
      else
        raise TypeError, "Invalid type for StoragePointer assignment"
      end
    else
      @state_manager.set(*new_path, value)
    end
  # rescue => e
  #   binding.pry
  end
  
  def get(key)
    key = VM.unbox(key)
    
    new_path = @path + [key]
    type = @state_manager.validate_and_get_type(new_path)
    
    if type.mapping? || type.array? || type.struct?
      StoragePointer.new(@state_manager, new_path)
    else
      @state_manager.get(*new_path)
    end
  # rescue => e
  #   binding.pry
  end
  
  def define_methods
    if @path.empty?
      define_top_level_methods
    else
      type = @state_manager.validate_and_get_type(@path)
      define_struct_methods(type) if type.name == :struct
    end
  end
  
  def define_top_level_methods
    @state_manager.state_var_layout.each_key do |key|
      define_singleton_method(key) do
        get(key)
      end

      define_singleton_method("#{key}=") do |value|
        set(key, value)
      end
    end
  end
  
  def define_struct_methods(struct_type)
    struct_type.struct_definition.fields.keys.each do |field|
      define_singleton_method(field) do
        get(field)
      end

      define_singleton_method("#{field}=") do |value|
        set(field, value)
      end
    end
  end
end
