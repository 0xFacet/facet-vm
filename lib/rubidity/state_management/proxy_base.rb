class ProxyBase
  attr_accessor :wrapper, :path, :raw_data
  
  def initialize(wrapper, *path, raw_data: nil)
    @wrapper = wrapper
    @path = ::VM.deep_unbox(path)
    @raw_data = raw_data
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
    property = property.to_s
    
    @wrapper.write(*@path, property, value)
  end
end

class StateProxyTwo < ProxyBase
  def initialize(wrapper)
    super(wrapper)
  end
end
