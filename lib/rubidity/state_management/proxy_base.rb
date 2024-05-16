class ProxyBase
  attr_accessor :wrapper, :path, :raw_data, :memory_var
  
  def initialize(wrapper, *path, memory_var: nil)
    @wrapper = wrapper
    @path = path #::VM.deep_unbox(path)
    @memory_var = memory_var
    @raw_data = memory_var.value.data if memory_var
  end
  
  def as_json
    if memory_var
      memory_var.as_json
    else
      raise "Can't serialize storage variable without memory_var"
    end
  end
  
  def eq(...)
    if memory_var
      memory_var.eq(...)
    else
      raise "Can't compare storage variable without memory_var"
    end
  end

  def [](key)
    @wrapper.read(*@path, key)
  end

  def []=(key, value)
    @wrapper.write(*@path, key, value)
  end 
  
  def method_missing(name, *args)
    if name[-1] == '='
      property = name[0..-2]
      value = args.first
      set_property(property, value)
    else
      get_property(name, *args)
    end
  # rescue => e
  #   binding.pry
  end

  def respond_to_missing?(name, include_private = false)
    true
  end

  def get
    @wrapper.read(*@path)
  end

  def set(value)
    @wrapper.write(*@path, value)
    value
  end

  def push(value)
    index = raw_data.nil? ? 0 : raw_data.length
    @wrapper.write(*@path, index, value)
  end

  def pop
    index = raw_data.length - 1
    value = @wrapper.read(*@path, index)
    @wrapper.write(*@path, index, nil)
    value
  end
  
  def length
    memory_var.type.length || raw_data.length
  end
  
  def last
    self[self.length - 1]
  end
  
  private

  def get_property(property, *args)
    property = property.to_s
    
    if args.empty?
      @wrapper.read(*@path, property)
    else
      @wrapper.read(*@path, property, *args)
    end

  end

  def set_property(property, value)
    # value = VM.unbox(value)
    # ap value
    
    property = property.to_s
    
    @wrapper.write(*@path, property, value)
  end
end
