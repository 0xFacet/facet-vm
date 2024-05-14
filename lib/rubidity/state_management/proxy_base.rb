class ProxyBase
  def initialize(wrapper, *path)
    @wrapper = wrapper
    @path = path
  end

  def [](key)
    self.class.new(@wrapper, *@path, key)
  end

  def []=(key, value)
    self.class.new(@wrapper, *@path, key).set(value)
  end
  
  def wrapper
    @wrapper
  end

  def method_missing(name, *args, &block)
    args = ::VM.deep_unbox(args)
    
    if name[-1] == '='
      property = name[0..-2]
      value = args.first
      set_property(property, value)
    else
      get_property(name, *args)
    end
  end

  def respond_to_missing?(name, include_private = false)
    true
  end

  def get
    @wrapper.read(*@path)
  end

  def set(value)
    # type = infer_type(value)
    # typed_value = TypedVariable.create(type, value)
    @wrapper.write(*@path, value)
    value
  end

  def push(value)
    # type = infer_type(value)
    # typed_value = TypedVariable.create(type, value)

    # Find the current length of the array
    array = @wrapper.read(*@path)
    index = array.nil? ? 0 : array.length

    # Insert the new value at the next available index
    @wrapper.write(*@path, index, value)
  end

  private

  def get_property(property, *args)
    if args.empty?
      @wrapper.read(*@path, property)
    else
      @wrapper.read(*@path, property, *args)
    end
  end

  def set_property(property, value)
    # type = infer_type(value)
    # typed_value = TypedVariable.create(type, value)
    @wrapper.write(*@path, property, value)
  end
end

class StateProxyTwo < ProxyBase
  def initialize(wrapper)
    super(wrapper)
  end
end
