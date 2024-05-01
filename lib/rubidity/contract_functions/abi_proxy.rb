class AbiProxy
  include ContractErrors
  
  attr_accessor :data, :contract_class
  
  def initialize(contract_class)
    @contract_class = contract_class
    @data = {}.with_indifferent_access
    
    merge_parent_state_variables
    merge_parent_abis
    merge_parent_events
  end
  
  def as_json
    data.map do |name, function_definition|
      function_definition.as_json.merge(name: name)
    end
  end
  
  def merge_parent_events
    parent_events = contract_class.linearized_parents.map(&:events).reverse
    contract_class.events = parent_events.reduce({}, :merge).merge(contract_class.events)
  end
  
  def merge_parent_state_variables
    parent_state_variables = contract_class.linearized_parents.map(&:state_variable_definitions).reverse
    contract_class.state_variable_definitions = parent_state_variables.reduce({}, :merge).merge(contract_class.state_variable_definitions)
  end
  
  def merge_parent_abis
    contract_class.linearized_parents.each do |parent|
      parent.abi.data.each do |name, func|
        prefixed_name = "__#{parent.name}_#{name}__"
        define_function_method(prefixed_name, func, contract_class)
        add_function(name, func, from_parent: true)
      end
    end
  end
  
  def add_function(name, new_function, from_parent: false)
    existing_function = @data[name]
    
    new_function.from_parent = from_parent
    
    if existing_function
      if existing_function.from_parent
        unless (existing_function.virtual? && new_function.override?) ||
               (existing_function.constructor? && new_function.constructor?) ||
               from_parent
          raise InvalidOverrideError, "Cannot override non-constructor parent function #{name} without proper modifiers (#{contract_class.name})"
        end
      else
        raise FunctionAlreadyDefinedError, "Function #{name} already defined in child!"
      end
    elsif new_function.override?
      raise InvalidOverrideError, "Function #{name} declared with override but does not override any parent function (#{contract_class.name})"
    end
  
    @data[name] = new_function
    define_function_method(name, new_function, contract_class)
  end
  
  def create_and_add_function(name, args, *options, returns: nil, &block)
    new_function = FunctionProxy.create(name, args, *options, returns: returns, contract_class: contract_class, &block)
    add_function(name, new_function)
  end
  
  private
  
  def define_function_method(method_name, func_proxy, target_class)
    target_class.class_eval do
      define_method(method_name) do |*args, **kwargs|
        begin
          cooked_args = func_proxy.convert_args_to_typed_variables_struct(args, kwargs)
          
          ret_val = nil
          
          state_manager.detecting_changes(revert_on_change: func_proxy.read_only?) do
            ret_val = FunctionContext.define_and_call_function_method(
              self, cooked_args, method_name, &func_proxy.implementation
            )
          end
          
          func_proxy.convert_return_to_typed_variable(ret_val)
        rescue Contract::ContractArgumentError, Contract::VariableTypeError => e
          # TODO
          c_locs = ::Kernel.instance_method(:caller_locations).bind(self).call
          caller_location = c_locs.detect { |location| location.path.ends_with?(".rubidity") }
          
          if caller_location
            file = caller_location.path.gsub(%r{.*/}, '')
            line = caller_location.lineno
            
            emphasized_code = ContractArtifact.emphasized_code_exerpt(name: file.split.first, line_number: line)
          end
          
          raise ContractError.new("Wrong args in #{method_name} (#{func_proxy.func_location}): #{e.message}\n\n#{emphasized_code}", self)
        rescue InvalidStateVariableChange
          raise ContractError,
          "Invalid change in read-only function: #{method_name}, #{(args.presence || kwargs).inspect}, to address: #{current_address}."
        end
      end
    end
  end
  
  def method_missing(name, *args, &block)
    if data.respond_to?(name)
      data.send(name, *args, &block)
    else
      super
    end
  end
  
  def respond_to_missing?(name, include_private = false)
    data.respond_to?(name, include_private) || super
  end
end
