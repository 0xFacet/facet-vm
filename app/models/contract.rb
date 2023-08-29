class Contract < ApplicationRecord
  include ContractErrors
    
  has_many :call_receipts, primary_key: 'contract_id', class_name: "ContractCallReceipt", dependent: :destroy
  has_many :states, primary_key: 'contract_id', class_name: "ContractState", dependent: :destroy
  
  belongs_to :ethscription, primary_key: 'ethscription_id', foreign_key: 'contract_id',
    class_name: "Ethscription", touch: true
  
  attr_accessor :current_transaction, :msg
  
  after_initialize :initialize_state_proxy

  class << self
    attr_accessor :state_variable_definitions, :parent_contracts, :events
  end
  
  delegate :block, :tx, :esc, to: :current_transaction
  
  class Message
    attr_reader :sender
    
    def sender=(address)
      @sender = TypedVariable.create(:addressOrDumbContract, address)
    end
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
  
  def initialize_state_proxy
    @state_proxy = StateProxy.new(self, self.class.state_variable_definitions)
  end
  
  def current_state
    states.newest_first.first || ContractState.new
  end
  
  def msg
    @msg ||= Message.new
  end
  
  def self.abi
    @abi ||= AbiProxy.new(self)
  end
  
  def abi
    self.class.abi
  end
  
  def execute_function(function_name, function_args)
    abi_entry = abi[function_name]
    
    begin
      with_state_management(read_only: abi_entry.read_only?) do
        send(function_name.to_sym, function_args.deep_symbolize_keys)
      end
    rescue ContractError => e
      e.contract = self
      raise e
    end
  end
  
  def with_state_management(read_only:)
    load_current_state
  
    yield.tap do
      if state_changed? && !read_only
        states.create!(
          ethscription_id: current_transaction.ethscription.ethscription_id,
          state: @state_proxy.serialize
        )
      end
    end
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
      raise ContractError.new(message, self)
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
  
  def self.all_abis
    contract_classes = valid_contract_types

    contract_classes.each_with_object({}) do |name, hash|
      contract_class = "Contracts::#{name}".constantize

      hash[contract_class.name] = contract_class.public_abi
    end.transform_keys(&:demodulize)
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
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :contract_id,
        ]
      )
    ).tap do |json|
      json['abi'] = public_abi.as_json
      
      json['current_state'] = current_state.state
      json['current_state']['contract_type'] = type.demodulize
      
      json['source_code'] = {
        language: 'ruby',
        code: source_code
      }
    end
  end
  
  def load_current_state
    @state_proxy.deserialize(current_state.state.deep_dup)
    @initial_state = @state_proxy.serialize
    self
  end
  
  def state_changed?
    @initial_state != @state_proxy.serialize
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
  
  def self.valid_contract_types
    Contracts.constants.map do |c|
      Contracts.const_get(c).to_s.demodulize
    end
  end
  
  def static_call(name, args = {})
    ContractTransaction.make_static_call(
      contract_id: contract_id, 
      function_name: name, 
      function_args: args
    )
  end

  def source_file
    ActiveSupport::Dependencies.autoload_paths.each do |base_folder|
      relative_path = "#{self.class.name.underscore}.rb"
      absolute_path = File.join(base_folder, relative_path)

      return absolute_path if File.file?(absolute_path)
    end
    nil
  end

  def source_code
    File.read(source_file) if source_file
  end
  
  protected

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
