class ContractImplementation < BasicObject
  include ::ContractErrors
  include ::ForLoop
  
  class << self
    attr_reader :name, :is_abstract_contract, :source_code,
    :init_code_hash, :parent_contracts, :available_contracts, :source_file,
    :is_upgradeable
    
    attr_accessor :state_variable_definitions, :events
  end
  
  delegate :block, :blockhash, :tx, :msg, :log_event, :call_stack,
           :current_address, to: :current_context
  
  attr_reader :current_context
  
  def initialize(current_context: ::TransactionContext, initial_state: nil)
    @current_context = current_context || raise("Must provide current context")
    
    if initial_state
      state_proxy.load(initial_state)
    end
  end
  
  def self.state_variable_definitions
    @state_variable_definitions ||= {}.with_indifferent_access
  end
  
  def s
    @state_proxy
  end
  
  def state_proxy
    @state_proxy ||= ::StateProxy.new(self.class.state_variable_definitions)
  end
  
  def self.abi
    @abi ||= ::AbiProxy.new(self)
  end
  
  ::Type.value_types.each do |type|
    define_singleton_method(type) do |*args|
      define_state_variable(type, args)
    end
  end
  
  def self.mapping(*args)
    key_type, value_type = args.first.first
    metadata = {key_type: key_type, value_type: value_type}
    type = ::Type.create(:mapping, metadata)
    
    if args.last.is_a?(::Symbol)
      define_state_variable(type, args)
    else
      type
    end
  end
  
  def self.array(*args, **kwargs)
    value_type = args.first
    metadata = {value_type: value_type}.merge(kwargs)
    
    if args.length == 2
      metadata.merge!(initial_length: args.last)
      args.pop
    end
    
    type = ::Type.create(:array, metadata)
    
    if args.length == 1
      type
    else
      define_state_variable(type, args)
    end
  end
  
  def array(value_type, initial_length = nil)
    metadata = { value_type: value_type }
    metadata.merge!(initial_length: initial_length) if initial_length
    
    type = ::Type.create(:array, metadata)
    ::TypedVariable.create(type)
  end
  
  def require(condition, message)
    unless condition == true || condition == false
      raise "Invalid truthy value for require"
    end
    
    return if condition == true
    
    c_locs = ::Kernel.instance_method(:caller_locations).bind(self).call
    
    caller_location = c_locs.detect do |location|
      location.path == self.class.name
    end || c_locs.detect do |location|
      self.class.linearized_parents.map(&:name).include?(location.path)
    end
    
    file = caller_location.path
    line = caller_location.lineno
    
    emphasized_code = ::ContractArtifact.emphasized_code_exerpt(name: file, line_number: line)
      
    error_message = "#{message}. (#{file}:#{line})\n\n#{emphasized_code}\n\n"
    raise ContractError.new(error_message, self)
  end
  
  def self.public_abi
    abi.select do |name, details|
      details.publicly_callable?
    end
  end
  
  def public_abi
    self.class.public_abi
  end
  
  def self.implements?(interface)
    return false unless interface
    
    interface.public_abi.all? do |function_name, details|
      actual = public_abi[function_name]
      actual && (actual.constructor? || actual.args == details.args)
    end
  end
  
  def self.linearize_contracts(contract)
    stack = [contract]
    linearized = []
  
    while stack.any?
      current = stack.last
      if linearized.include?(current)
        stack.pop
        next
      end
  
      unprocessed_parents = current.parent_contracts.reject { |parent| linearized.include?(parent) }
  
      if unprocessed_parents.empty?
        linearized << stack.pop
      else
        stack.push(*unprocessed_parents)
      end
    end
  
    linearized
  end
  
  def self.linearized_parents
    linearize_contracts(self).dup.tap(&:pop)
  end
  
  def self.function(name, args, *options, returns: nil, &block)
    if args.is_a?(::Symbol)
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
    type = ::Type.create(type)
    
    if state_variable_definitions[name]
      raise "No shadowing: #{name} is already defined."
    end
    
    state_variable_definitions[name] = { type: type, args: args }
    
    state_var = ::StateVariable.create(name, type, args)
    state_var.create_public_getter_function(self)
  end
  
  def keccak256(input)
    input = ::TypedVariable.create_or_validate(:bytes, input)
    
    bin_input = ::Eth::Util.hex_to_bin(input.value)
    
    hash = ::Digest::Keccak256.hexdigest(bin_input)
    
    ::TypedVariable.create_or_validate(:bytes32, "0x" + hash)
  end
  
  def type(var)
    if var.is_a?(::TypedObject) && var.type.contract?
      var = var.contract_type
    end
    
    contract_class = self.class.available_contracts[var]
    
    unless contract_class
      raise "Unknown contract"
    end
    
    if contract_class.is_abstract_contract
      raise "Cannot instantiate abstract contract"
    end
  end
  
  def public_send(...)
    ::Object.instance_method(:public_send).bind(self).call(...)
  end
  
  def send(...)
    ::Object.instance_method(:send).bind(self).call(...)
  end
  
  private

  def json
    ::Object.new.tap do |proxy|
      def proxy.stringify(*args, **kwargs)
        res = (args.presence || kwargs).to_json
        ::TypedVariable.create(:string, res)
      end
    end
  end
  
  def abi
    ::Object.new.tap do |proxy|
      def proxy.encodePacked(*args)
        res = args.map do |arg|
          bytes = arg.toPackedBytes
          bytes = bytes.value.sub(/\A0x/, '')
        end.join
        
        ::TypedVariable.create(:bytes, "0x" + res)
      end
    end
  end
  
  def string(i)
    if i.is_a?(::TypedObject) && i.type.is_value_type?
      return ::TypedVariable.create(:string, i.value.to_s)
    else
      raise "Input must be typed"
    end
  end
  
  def address(i)
    if i.is_a?(::TypedObject) && i.type.contract?
      return ::TypedVariable.create(:address, i.value.address)
    end
    
    if i.is_a?(::Integer) && i == 0
      return ::TypedVariable.create(:address) 
    end
    
    if i.is_a?(::TypedObject) && i.type.address?
      return i
    end
    
    raise "Not implemented"
  end
  
  def bytes32(i)
    if i == 0
      return ::TypedVariable.create(:bytes32)
    else
      raise "Not implemented"
    end
  end
  
  def self.calculate_new_contract_address_with_salt(salt, from_address, to_contract_init_code_hash)
    from_address = ::TypedVariable.validated_value(:address, from_address).sub(/\A0x/, '')
    salt = ::TypedVariable.validated_value(:bytes32, salt).sub(/\A0x/, '')
    to_contract_init_code_hash = ::TypedVariable.validated_value(
      :bytes32,
      to_contract_init_code_hash
    ).sub(/\A0x/, '')

    padded_from = from_address.rjust(64, "0")
    
    data = "0xff" + padded_from + salt + to_contract_init_code_hash

    hash = ::Digest::Keccak256.hexdigest(::Eth::Util.hex_to_bin(data))

    "0x" + hash.last(40)
  end
  
  def create2_address(salt:, deployer:, contract_type:)
    to_contract_init_code_hash = self.class.available_contracts[contract_type].init_code_hash
    
    self.class.calculate_new_contract_address_with_salt(salt, deployer, to_contract_init_code_hash)
  end
  
  def downcast_integer(integer, target_bits)
    integer = ::TypedVariable.create_or_validate(:uint256, integer)
    new_val = integer.value % (2 ** target_bits)
    ::TypedVariable.create(:"uint#{target_bits}", new_val)
  end
  
  (8..256).step(8).flat_map do |bits|
    define_method("uint#{bits}") do |integer|
      downcast_integer(integer, bits)
    end
  end
  
  def sqrt(integer)
    integer = ::TypedVariable.create_or_validate(:uint256, integer)

    ::Math.sqrt(integer.value.to_d).floor
  end
  
  def new(contract_initializer)
    if contract_initializer.is_a?(::TypedObject) && contract_initializer.type.contract?
      contract_initializer = {
        to_contract_type: contract_initializer.contract_type,
        args: contract_initializer.uncast_address,
      }
    elsif contract_initializer.respond_to?("__proxy_name__")
      contract_initializer = {
        to_contract_type: contract_initializer.__proxy_name__
      }
    end
    
    to_contract_type = contract_initializer.delete(:to_contract_type)
    target_implementation = self.class.available_contracts[to_contract_type]
    
    addr = call_stack.execute_in_new_frame(
      **contract_initializer.merge(
        type: :create,
        to_contract_init_code_hash: target_implementation.init_code_hash,
        to_contract_source_code: target_implementation.source_code,
      )
    )
    
    handle_contract_type_cast(
      to_contract_type,
      addr
    )
  end
  
  def create_contract_initializer(type, args)
    if args.is_a?(::Hash)
      return {
        to_contract_type: type, 
        args: args,
      }
    end
    
    input_args = args.select { |arg| !arg.is_a?(::Hash) }
    options = args.reverse.detect { |arg| arg.is_a?(::Hash) } || {}
    
    input_salt = options[:salt]
    
    {
      to_contract_type: type, 
      args: input_args,
      salt: input_salt
    }
  end
  
  def method_missing(method_name, *args, **kwargs, &block)
    unless self.class.available_contracts.include?(method_name)
      raise ::NoMethodError.new("undefined method `#{method_name}' for #{self.class.name}", method_name)
    end
    
    if args.many? || (args.blank? && kwargs.present?) || (args.one? && args.first.is_a?(::Hash))
      create_contract_initializer(method_name, args.presence || kwargs)
    elsif args.one?
      handle_contract_type_cast(method_name, args.first)
    else
      contract_instance = self
      potential_parent = self.class.available_contracts[method_name]
      
      ::Object.new.tap do |proxy|
        proxy.define_singleton_method("__proxy_name__") do
          method_name
        end
        
        potential_parent.abi.data.each do |name, _|
          proxy.define_singleton_method(name) do |*args, **kwargs|
            contract_instance.send("__#{potential_parent.name}__#{name}", *args, **kwargs)
          end
        end
      end
    end
  end

  def self.respond_to_missing?(method_name, include_private = false)
    available_contracts.include?(method_name) || super
  end

  def this
    handle_contract_type_cast(self.class.name, current_address)
  end
  
  def handle_contract_type_cast(contract_type, other_address)
    proxy = ::ContractVariable::Value.new(
      contract_class: self.class.available_contracts[contract_type],
      address: other_address
    )
    
    ::TypedVariable.create(:contract, proxy)
  end
  
  def self.inspect
    "#<#{name}:#{object_id}>"
  end
  
  def class
    ::Object.instance_method(:class).bind(self).call
  end
  
  def raise(...)
    ::Kernel.instance_method(:raise).bind(self).call(...)
  end
end
