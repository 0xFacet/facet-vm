class ContractImplementation
  include ContractErrors
  class << self
    attr_accessor :state_variable_definitions, :parent_contracts,
    :events, :is_abstract_contract, :source_code, :is_main_contract, :file_source_code
  end
  
  delegate :block, :blockhash, :tx, :esc, :msg, :log_event,
           :current_address, to: :current_context
  delegate :implements?, :state_variable_definitions, to: :class
  
  attr_reader :current_context
  
  def initialize(current_context: TransactionContext)
    @current_context = current_context || raise("Must provide current context")
  end
  
  # def attach_contract_record(address = nil)
  #   @contract_record = Contract.new(address: address, type: self.class.name.demodulize)
  # end
  
  # def self.mock
  #   Contract.new(type: self.name.demodulize).implementation
  # end
  
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
    @state_proxy ||= StateProxy.new(state_variable_definitions)
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
    
    if args.length == 1
      type
    else
      define_state_variable(type, args)
    end
  end
  
  def array(value_type, initial_length = nil)
    metadata = { value_type: value_type }
    metadata.merge!(initial_length: initial_length) if initial_length
    
    type = Type.create(:array, metadata)
    TypedVariable.create(type)
  end
  
  def require(condition_or_block, message)
    contract_path = '/app/models/contracts'
    spec_path = '/spec/models'
    
    possible_paths = Rails.env.test? ? [contract_path, spec_path] : [contract_path]
    
    caller_location = nil
    possible_paths.each do |path|
      caller_location = caller_locations.detect { |location| location.path.include?(path) }
      break if caller_location
    end
  # binding.pry
    if caller_location.path.include?("rubidity_interpreter_spec")
      caller_location = caller_locations.detect { |location| location.path.include?(self.class.name)}
    end
    
    file = caller_location.path.gsub(%r{.*/}, '') 
    line = caller_location.lineno
    # binding.pry
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
  
  def self.types_that_implement(base_type)
    impl = ContractImplementation.main_contracts.detect{|i| i.name == base_type.to_s}
    deployable_contracts.select do |contract|
      contract.implements?(impl)
    end.map(&:name)
  end
  
  def self.implements?(interface)
    return false unless interface
    
    interface.public_abi.all? do |function_name, details|
      actual = public_abi[function_name]
      actual && (actual.constructor? || actual.args == details.args)
    end
  end  
  
  def self.main_contracts
    VALID_CONTRACTS.select{|k,v| v.is_main_contract }.values
  end
  
  def self.deployable_contracts
    main_contracts.reject(&:is_abstract_contract)
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
    if args.is_a?(Symbol)
      options.unshift(args)
      args = {}
    end
    
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

    log_event({
      contractType: self.class.name,
      contractAddress: current_address,
      event: event_name,
      data: args
    })
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
  
  def keccak256(input)
    input = input.to_s(16) if input.is_a?(Integer)
    
    str = TypedVariable.create(:string, input)
    
    "0x" + Digest::Keccak256.new.hexdigest(str.value)
  end
  
  def self.available_contracts
    @available_contracts ||= {}.with_indifferent_access
  end
  
  protected

  def abi
    Object.new.tap do |proxy|
      def proxy.encodePacked(*args)
        args.map do |arg|
          arg = Integer(arg, 16)
          arg.to_s(16).rjust(64, '0')
        end.join
      end
    end
  end
  
  def string(i)
    if i.is_a?(TypedVariable) && i.type.is_value_type?
      return TypedVariable.create(:string, i.value.to_s)
    else
      raise "Input must be typed"
    end
  end
  
  def address(i)
    if i.is_a?(TypedVariable) && i.type.is_contract_type?
      return TypedVariable.create(:address, i.value.address)
    end
    
    if i.is_a?(TypedVariable) && i.type.contract?
      return TypedVariable.create(:address, i.value.address)
    end
    
    if i.is_a?(Integer) && i == 0
      return TypedVariable.create(:address) 
    end
    
    if i.is_a?(TypedVariable) && i.type.address?
      return i
    end
    
    raise "Not implemented"
  end
  
  def bytes32(i)
    if i == 0
      return TypedVariable.create(:bytes32)
    else
      raise "Not implemented"
    end
  end
  
  def self.calculate_new_contract_address_with_salt(salt, from_address, to_contract_type)
    unless Contract.type_valid?(to_contract_type)
      raise TransactionError.new("Invalid contract type: #{to_contract_type}")
    end
    
    salt_hex = Integer(salt, 16).to_s(16)
    padded_from = from_address.to_s[2..-1].rjust(64, "0")
    bytecode_simulation = Eth::Util.hex_to_bin(Digest::Keccak256.new.hexdigest(to_contract_type))
    
    data = "0xff" + padded_from + salt_hex + Digest::Keccak256.new.hexdigest(bytecode_simulation)

    hash = Digest::Keccak256.new.hexdigest(Eth::Util.hex_to_bin(data))

    "0x" + hash[24..-1]
  end
  
  def create2_address(salt:, deployer:, contract_type:)
    self.class.calculate_new_contract_address_with_salt(salt, deployer, contract_type)
  end
  
  def downcast_integer(integer, target_bits)
    integer = TypedVariable.create_or_validate(:uint256, integer)
    new_val = integer.value % (2 ** target_bits)
    TypedVariable.create(:"uint#{target_bits}", new_val)
  end
  
  (8..256).step(8).flat_map do |bits|
    define_method("uint#{bits}") do |integer|
      downcast_integer(integer, bits)
    end
  end
  
  def sqrt(integer)
    integer = TypedVariable.create_or_validate(:uint256, integer)

    Math.sqrt(integer.value.to_d).floor
  end
  
  def new(contract_initializer)
    if contract_initializer.is_a?(TypedVariable)
      contract_initializer = if contract_initializer.type.contract?
        {
          to_contract_type: contract_initializer.contract_type,
          args: contract_initializer.uncast_address,
        }
      else
        {
          to_contract_type: contract_initializer.type.name,
          args: contract_initializer.uncast_address,
        }
      end
    elsif contract_initializer.respond_to?("__proxy_name__")
      contract_initializer = {
        to_contract_type: contract_initializer.__proxy_name__
      }
    end
    
    TransactionContext.call_stack.execute_in_new_frame(
      **contract_initializer.merge(type: :create)
    )
    
    # TODO
    addr = TransactionContext.current_transaction.contract_calls.last.created_contract_address
    
    handle_contract_type_cast(
      contract_initializer[:to_contract_type].to_sym,
      addr
    )
  end
  
  def create_contract_initializer(type, args)
    if args.is_a?(Hash)
      return {
        to_contract_type: type, 
        args: args,
      }
    end
    
    input_args = args.select { |arg| !arg.is_a?(Hash) }
    options = args.detect { |arg| arg.is_a?(Hash) } || {}
    
    input_salt = options[:salt]
    
    {
      to_contract_type: type, 
      args: input_args,
      salt: input_salt
    }
  end
  
  def method_missing(method_name, *args, **kwargs, &block)
    unless self.class.available_contracts.include?(method_name)
      raise NoMethodError.new("undefined method `#{method_name}' for #{self.class.name}", method_name)
    end
    
    if args.many? || (args.blank? && kwargs.present?) || args.last.is_a?(Hash) || (args.one? && args.first.is_a?(Hash))
      create_contract_initializer(method_name, args.presence || kwargs)
    elsif args.one?
      handle_contract_type_cast(method_name, args.first)
    else
      contract_instance = self
      parent = self.class.available_contracts[method_name]
      
      Object.new.tap do |proxy|
        proxy.define_singleton_method("__proxy_name__") do
          method_name
        end
        
        parent.abi.data.each do |name, _|
          proxy.define_singleton_method(name) do |*args, **kwargs|
            contract_instance.send("__#{parent.name.demodulize}__#{name}", *args, **kwargs)
          end
        end
      end
    end
  end

  def self.respond_to_missing?(method_name, include_private = false)
    available_contracts.include?(method_name) || super
  end

  def this
    handle_contract_type_cast(self.class.name.demodulize, current_address)
  end
  
  def handle_contract_type_cast(contract_type, other_address)
    # proxy = ContractType::Proxy.new(
    #   contract_type: contract_type,
    #   address: other_address
    # )
    
    # TypedVariable.create(contract_type, proxy)
    
    proxy = ContractType::Proxy.new(
      contract_type: contract_type,
      contract_interface: self.class.available_contracts[contract_type],
      address: other_address
    )
    
    TypedVariable.create(:contract, proxy)
  end
  
  def self.inspect
    "#<#{name.demodulize}:#{object_id}>"
  end
  
  VALID_CONTRACTS = RubidityInterpreter.build_valid_contracts
end
