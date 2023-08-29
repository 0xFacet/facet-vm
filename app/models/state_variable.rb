class StateVariable
  include ContractErrors
  
  attr_accessor :typed_variable, :name, :visibility, :immutable, :constant
  
  def initialize(name, typed_variable, args)
    visibility = :internal
    
    args.each do |arg|
      case arg
      when :public, :private
        visibility = arg
      end
    end
    
    @visibility = visibility
    @immutable = args.include?(:immutable)
    @constant = args.include?(:constant)
    @name = name
    @typed_variable = typed_variable
  end
  
  def self.create(name, type, args)
    var = TypedVariable.create(type)
    new(name, var, args)
  end
  
  def create_public_getter_function(contract_class)
    return unless @visibility == :public
    new_var = self
    
    if type.mapping?
      create_mapping_getter_function(contract_class)
    elsif type.array?
      create_array_getter_function(contract_class)
    else
      contract_class.class_eval do
        self.function(new_var.name, {}, :public, :view, returns: new_var.type.name) do
          s.send(new_var.name)
        end
      end
    end
  end
  
  def create_mapping_getter_function(contract_class)
    arguments = {}
    current_type = type
    index = 0
    new_var = self
    
    while current_type.name == :mapping
      arguments["arg#{index}".to_sym] = current_type.key_type.name
      current_type = current_type.value_type
      index += 1
    end
    
    contract_class.class_eval do
      self.function(new_var.name, arguments, :public, :view, returns: current_type.name) do
        value = s.send(new_var.name)
        (0...index).each do |i|
          value = value[send("arg#{i}".to_sym)]
        end
        value
      end
    end
  end
  
  def create_array_getter_function(contract_class)
    current_type = type
    new_var = self
  
    contract_class.class_eval do
      self.function(new_var.name, {index: :uint256}, :public, :view, returns: current_type.value_type.name) do
        value = s.send(new_var.name)
        value[send(:index)]
      end
    end
  end
  
  def serialize
    typed_variable.serialize
  end
  
  def deserialize(value)
    typed_variable.deserialize(value)
  end
  
  def method_missing(name, *args, &block)
    if typed_variable.respond_to?(name)
      typed_variable.send(name, *args, &block)
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    typed_variable.respond_to?(name, include_private) || super
  end
  
  def ==(other)
    other.is_a?(self.class) &&
      typed_variable == other.typed_variable &&
      name == other.name &&
      visibility == other.visibility &&
      immutable == other.immutable &&
      constant == other.constant
  end
  
  def !=(other)
    !(self == other)
  end
  
  def hash
    [typed_variable, name, visibility, immutable, constant].hash
  end

  def eql?(other)
    hash == other.hash
  end
end
