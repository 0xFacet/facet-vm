# TODO: put behind save proxy
class StoragePointer
  attr_accessor :state_manager, :path
  
  def initialize(state_manager, path = [])
    @state_manager = state_manager
    @path = path
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
  
  def push(value)
    validate_array!
    value = VM.unbox(value)
    
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
    load_array
  end
  
  def validate_array!
    type = @state_manager.validate_and_get_type(@path)
    raise TypeError, "Cannot duplicate non-array type" unless type.name == :array
  end

  def set_array(new_array)
    # Pop all existing values
    while length.value > 0
      pop
    end

    # Push new values
    new_array.value.data.each do |element|
      push(element)
    end
  end
  
  private

  def set(key, value)
    key = VM.unbox(key)
    value = VM.unbox(value)
    
    new_path = @path + [key]
    
    type = @state_manager.validate_and_get_type(new_path)

    if value.is_a?(ArrayVariable) && type.name == :array
      StoragePointer.new(@state_manager, new_path).set_array(value)
    else
      @state_manager.set(*new_path, value)
    end
  end
  
  def get(key)
    key = VM.unbox(key)
    
    new_path = @path + [key]
    type = @state_manager.validate_and_get_type(new_path)
    
    if type.name == :mapping || type.name == :array
      StoragePointer.new(@state_manager, new_path)
    else
      @state_manager.get(*new_path)
    end
  end
end
