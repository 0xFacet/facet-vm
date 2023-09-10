class ContractImplementation
  include ContractErrors
    
  attr_reader :contract_record
  
  class << self
    attr_accessor :state_variable_definitions, :parent_contracts,
    :events, :is_abstract_contract, :valid_contract_types
  end
  
  delegate :block, :blockhash, :tx, :esc, :msg, :log_event, :this, to: TransactionContext
  delegate :implements?, to: :class
  
  def initialize(contract_record)
    @state_proxy = StateProxy.new(
      contract_record,
      contract_record.implementation_class.state_variable_definitions
    )
    
    @contract_record = contract_record
  end
  
  def self.mock
    Contract.new(type: self.name).implementation
  end
  
  def self.abstract
    @is_abstract_contract = true
  end
  
  def self.state_variable_definitions
    @state_variable_definitions ||= {}
  end
  
  def self.parent_contracts
    @parent_contracts ||= []
  end
  
  def s
    @state_proxy
  end
  
  def state_proxy
    @state_proxy
  end
  
  def self.const_missing(name)
    return super unless TransactionContext.current_contract
    
    TransactionContext.current_contract.implementation.tap do |impl|
      valid_methods = impl.class.linearized_parents.map{|p| p.name.demodulize.to_sym }
      
      return valid_methods.include?(name) ? impl.send(name) : super
    end
  end
  
  def self.abi
    @abi ||= AbiProxy.new(self)
  end
  
  Type.value_types.each do |type|
    define_singleton_method(type) do |*args|
      define_state_variable(type, args)
    end
  end
  
  def self.mapping(*args)
    key_type, value_type = args.first.first
    metadata = {key_type: key_type, value_type: value_type}
    type = Type.create(:mapping, metadata)
    
    if args.last.is_a?(Symbol)
      define_state_variable(type, args)
    else
      type
    end
  end
  
  def self.array(*args)
    value_type = args.first
    metadata = {value_type: value_type}
    type = Type.create(:array, metadata)
    
    define_state_variable(type, args)
  end
  
  def require(condition_or_block, message)
    caller_location = caller_locations.detect { |l| l.path.include?('/app/models/contracts') }
    file = caller_location.path.gsub(%r{.*app/models/contracts/}, '')
    line = caller_location.lineno
  
    if condition_or_block.is_a?(Proc)
      begin
        condition_result = condition_or_block.call
      rescue => e
        error_message = "Exception during condition evaluation: #{e.message}. (#{file}:#{line})"
        raise ContractError.new(error_message, self)
      end
  
      unless condition_result
        error_message = "#{message}. (#{file}:#{line})"
        raise ContractError.new(error_message, self)
      end
    else
      unless condition_or_block
        error_message = "#{message}. (#{file}:#{line})"
        raise ContractError.new(error_message, self)
      end
    end
  end
  
  def self.public_abi
    abi.select do |name, details|
      details.publicly_callable?
    end
  end
  
  def public_abi
    self.class.public_abi
  end
  
  def self.is(*constants)
    self.parent_contracts += constants.map{|i| "Contracts::#{i}".constantize}
    self.parent_contracts = self.parent_contracts.uniq
  end
  
  def self.implements?(contract)
    class_name = "Contracts::#{contract}".constantize
    parent_contracts.include?(class_name) || self == class_name
  end
  
  def self.linearize_contracts(contract, processed = [])
    return [] if processed.include?(contract)
  
    new_processed = processed + [contract]
  
    return [contract] if contract.parent_contracts.empty?
    linearized = [contract] + contract.parent_contracts.reverse.flat_map { |parent| linearize_contracts(parent, new_processed) }
    linearized.uniq { |c| raise "Invalid linearization" if linearized.rindex(c) != linearized.index(c); c }
  end
  
  def self.linearized_parents
    linearize_contracts(self)[1..-1]
  end
  
  def self.function(name, args, *options, returns: nil, &block)
    abi.create_and_add_function(name, args, *options, returns: returns, &block)
  end
  
  def self.constructor(args = {}, *options, &block)
    function(:constructor, args, *options, returns: nil, &block)
  end
  
  def self.event(name, args)
    @events ||= {}
    @events[name] = args
  end

  def self.events
    @events || {}.with_indifferent_access
  end

  def emit(event_name, args = {})
    unless self.class.events.key?(event_name)
      raise ContractDefinitionError.new("Event #{event_name} is not defined in this contract.", self)
    end

    expected_args = self.class.events[event_name]
    missing_args = expected_args.keys - args.keys
    extra_args = args.keys - expected_args.keys

    if missing_args.any? || extra_args.any?
      error_messages = []
      error_messages << "Missing arguments for #{event_name} event: #{missing_args.join(', ')}." if missing_args.any?
      error_messages << "Unexpected arguments provided for #{event_name} event: #{extra_args.join(', ')}." if extra_args.any?
      raise ContractDefinitionError.new(error_messages.join(' '), self)
    end

    log_event({ event: event_name, data: args })
  end

  def self.define_state_variable(type, args)
    name = args.last.to_sym
    type = Type.create(type)
    
    if state_variable_definitions[name]
      raise "No shadowing: #{name} is already defined."
    end
    
    state_variable_definitions[name] = { type: type, args: args }
    
    state_var = StateVariable.create(name, type, args)
    state_var.create_public_getter_function(self)
  end
  
  def self.pragma(*args)
    # Do nothing for now
  end
  
  def keccak256(input)
    str = TypedVariable.create(:string, input)
    
    "0x" + Digest::Keccak256.new.hexdigest(str.value)
  end
  
  protected

  def string(i)
    if i.is_a?(TypedVariable) && i.type.is_value_type?
      return TypedVariable.create(:string, i.value.to_s)
    else
      raise "Input must be typed"
    end
  end
  
  def address(i)
    if i.is_a?(ContractImplementation) && i == self
      return TypedVariable.create(:address, contract_record.address)
    end
    
    if i.is_a?(Integer) && i == 0
      return TypedVariable.create(:address) 
    end
    
    if i.is_a?(TypedVariable) && i.type.address?
      return i
    end
    
    raise "Not implemented"
  end
  
  def self.inherited(subclass)
    super
    
    method_name = subclass.name.demodulize.to_sym
    
    if Contracts.constants.include?(method_name)
      define_method(method_name) do |other_address|
        handle_contract_type_cast(method_name, other_address)
      end
      
      self.valid_contract_types ||= []
      self.valid_contract_types << method_name
      
      Type::TYPES << method_name unless Type::TYPES.include?(method_name)
    end
  end

  def handle_contract_type_cast(contract_type, other_address)
    proxy = ContractType::Proxy.new(
      contract_type: contract_type,
      address: other_address,
      caller_address: contract_record.address
    )
    
    TypedVariable.create(contract_type, proxy)
  end
end
