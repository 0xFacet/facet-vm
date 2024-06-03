class StateVariable
  include ContractErrors
  include InstrumentAllMethods
  
  attr_accessor :name, :visibility, :immutable, :constant, :type
  
  def initialize(name, type, args)
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
    
    @type = type
  end
  
  def self.create(name, type, args)
    new(name, type, args)
  end
  
  def create_public_getter_function(contract_class)
    return unless @visibility == :public
    new_var = self
    
    contract_class.expose(name)
    
    if type.mapping?
      create_mapping_getter_function(contract_class)
    elsif type.array?
      create_array_getter_function(contract_class)
    else
      contract_class.class_eval do
        self.function(new_var.name, {}, :public, :view, returns: new_var.type.name) do
          s.handle_call_from_proxy(new_var.name)
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
  
    if current_type.array?
      arguments["arg#{index}".to_sym] = :uint256
      current_type = current_type.value_type
      index += 1
    end
  
    contract_class.class_eval do
      self.function(new_var.name, arguments, :public, :view, returns: current_type.name) do
        value = s.handle_call_from_proxy(new_var.name)
        (0...index).each do |i|
          value = value[__send__("arg#{i}".to_sym)]
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
        value = s.handle_call_from_proxy(new_var.name)
        value[__send__(:index)]
      end
    end
  end
end
