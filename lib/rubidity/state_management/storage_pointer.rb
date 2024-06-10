class StoragePointer
  include DefineMethodHelper
  include Exposable
  
  attr_accessor :state_manager, :path
  
  expose :length, :last, :push, :pop, :eq, :ne,
   :[], :[]=
  
  def handle_call_from_proxy(method_name, *args, **kwargs)
    if method_exposed?(method_name)
      public_send(method_name, *args, **kwargs)
    else
      dynamic_method_handler(method_name, *args, **kwargs)
    end
  end
  
  def dynamic_method_handler(method_name, *args, **kwargs)
    if @path.empty?
      handle_dynamic_method(@state_manager.state_var_layout, method_name, *args, **kwargs)
    else
      type = @state_manager.validate_and_get_type(@path)
      if type.struct?
        handle_dynamic_method(type.struct_definition.fields, method_name, *args, **kwargs)
      else
        raise ContractError, "Function #{method_name} not exposed in Storage Pointer"
      end
    end
  end
  
  def handle_dynamic_method(methods_hash, method_name, *args, **kwargs)
    if method_name[-1] == "="
      chomped_method_name = method_name[0..-2]
      if methods_hash.key?(chomped_method_name)
        set(chomped_method_name, args.first)
      else
        raise NoMethodError, "Undefined method `#{method_name}` for #{self}"
      end
    else
      chomped_method_name = method_name
      if methods_hash.key?(chomped_method_name)
        get(chomped_method_name)
      else
        raise NoMethodError, "Undefined method `#{method_name}` for #{self}"
      end
    end
  end
  
  def initialize(state_manager, path = [])
    @state_manager = state_manager
    @path = path
  end
  
  def label
    label = current_type.is_a?(Hash) ?
      "Base" :
      current_type.raw_name
  end
  
  def [](key)
    get(key)
  end

  def []=(key, value)
    set(key, value)
  end
  
  def respond_to_missing?(name, include_private = false)
    true
  end
  
  def load_array
    TransactionContext.log_call("StoragePointer", label, "load_array") do
      length.as_json.times.map do |index|
        self[TypedVariable.create(:uint256, index)].as_json
        end.deep_dup
    end
  end
  
  def current_type
    @state_manager.validate_and_get_type(@path)
  end
  
  def load_struct
    TransactionContext.log_call("StoragePointer", label, "load_struct") do
      struct_type = @state_manager.validate_and_get_type(@path)
      raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?

      data = struct_type.struct_definition.fields.keys.each_with_object({}) do |field, hash|
        hash[field] = self[field]
      end.deep_dup
      
      # value = StructVariable::Value.new(values: data, struct_definition: struct_type.struct_definition)
      
      StructVariable.new(struct_type, data)
    end
  end
  
  def push(value)
    TransactionContext.log_call("StoragePointer", label, "push") do
      TransactionContext.increment_gas("StoragePointer#{label.to_s.upcase_first}Push")
      
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
  end

  def pop
    TransactionContext.log_call("StoragePointer", label, "pop") do
      TransactionContext.increment_gas("StoragePointer#{label.to_s.upcase_first}Pop")
      
      validate_array!
      @state_manager.array_pop(*@path)
    end
  end

  def length
    TransactionContext.log_call("StoragePointer", label, "length") do
      TransactionContext.increment_gas("StoragePointer#{label.to_s.upcase_first}Push")

      validate_array!
      @state_manager.array_length(*@path)
    end
  end
  
  def last
    TransactionContext.log_call("StoragePointer", label, "last") do
      TransactionContext.increment_gas("StoragePointer#{label.to_s.upcase_first}Push")

      validate_array!
      self[self.length - TypedVariable.create(:uint256, 1)]
    end
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
    TransactionContext.log_call("StoragePointer", label, "set_array") do
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
  end
  
  def log_call(method_name)
    TransactionContext.log_call("StoragePointer", label, method_name) do
      TransactionContext.increment_gas("StoragePointer#{label.to_s.upcase_first}#{method_name.to_s.upcase_first}")
      yield
    end
  end
  
  def eq(other)
    log_call("eq") do
      struct_type = @state_manager.validate_and_get_type(@path)
      raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?
      
      other = VM.unbox(other)
      
      load_struct.eq(other)
    end
  end
  
  def ne(other)
    TransactionContext.log_call("StoragePointer", label, "ne") do
      struct_type = @state_manager.validate_and_get_type(@path)
      raise TypeError, "Expected a struct type, got #{struct_type.name}" unless struct_type.struct?
      
      other = VM.unbox(other)
      
      load_struct.ne(other)
    end
  end
  
  def set_struct(new_struct)
    TransactionContext.log_call("StoragePointer", label, "set_struct") do
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
    end
  end
  
  private

  def set(key, value)
    TransactionContext.log_call("StoragePointer", label, "set") do
      TransactionContext.increment_gas("Storage#{label.to_s.upcase_first}Set")
      
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
    end
  # rescue => e
  #   binding.pry
  end
  
  def get(key)
    TransactionContext.log_call("StoragePointer", label, "get") do
      TransactionContext.increment_gas("Storage#{label.to_s.upcase_first}Get")
      key = VM.unbox(key)
      
      new_path = @path + [key]
      type = @state_manager.validate_and_get_type(new_path)
      
      if type.mapping? || type.array? || type.struct?
        StoragePointer.new(@state_manager, new_path)
      else
        @state_manager.get(*new_path)
      end
    end
  # rescue => e
  #   binding.pry
  end
end
