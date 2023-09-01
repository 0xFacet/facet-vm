class ContractImplementation
  include ContractErrors
    
  attr_reader :contract_record
  
  class << self
    attr_accessor :state_variable_definitions, :parent_contracts, :events, :is_abstract_contract
  end
  
  delegate :block, :tx, :esc, to: :current_transaction
  delegate :current_transaction, :contract_id, to: :contract_record
  
  def initialize(contract_record)
    @state_proxy = StateProxy.new(
      contract_record,
      contract_record.type.constantize.state_variable_definitions
    )
    
    @contract_record = contract_record
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
  
  def msg
    @msg ||= ContractTransactionGlobals::Message.new
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
  
  def require(condition, message)
    unless condition
      caller_location = caller_locations.detect { |l| l.path.include?('/app/models/contracts') }
      file = caller_location.path.gsub(%r{.*app/models/contracts/}, '')
      line = caller_location.lineno
      
      error_message = "#{message}. (#{file}:#{line})"
      raise ContractError.new(error_message, self)
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
    self.parent_contracts += constants.map{|i| "Contracts::#{i}".safe_constantize}
    self.parent_contracts = self.parent_contracts.uniq
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
  
  def self.constructor(args, *options, &block)
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

    current_transaction.log_event({ event: event_name, data: args })
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
    return TypedVariable.create(:address) if i == 0

    if i.is_a?(TypedVariable) && i.type == Type.create(:addressOrDumbContract)
      return TypedVariable.create(:address, i.value)
    end
    
    raise "Not implemented"
  end
  
  def addressOrDumbContract(i)
    return TypedVariable.create(:addressOrDumbContract) if i == 0
    raise "Not implemented"
  end
  
  def DumbContract(contract_id)
    current_transaction.create_execution_context_for_call(contract_id, self.contract_id)
  end
  
  def dumbContractId(i)
    return contract_id if i == self
    raise "Not implemented"
  end
end
