class ParsedContractFunction
  extend Memoist
  extend RuboCop::AST::NodePattern::Macros
  class InvalidFunctionBody < StandardError; end
  
  BASIC_METHODS = [:+, :*, :-, :<, :>, :/, :%, :>=, :<=, :!, :**, :!=, :==, :&, :|, :^, :div].to_set.freeze
  
  attr_accessor :contract, :name, :arguments, :visibility, :state_mutation,
    :return_type, :body, :original_node
  
  delegate :available_contracts, :state_variables, :calculated_state_variables,
    :calculated_available_contracts, to: :contract  
  
  def_node_matcher :function_arg_reference?, <<~PATTERN
    (send nil? $#function_arg?)
  PATTERN
  
  def_node_matcher :call_to_function_arg?, <<~PATTERN
    (send (send nil? $#function_arg?) $...)
  PATTERN
  
  def_node_matcher :call_to_parent_contract?, <<~PATTERN
    (send (const nil? $#parent_contract?) $...)
  PATTERN
  
  def_node_matcher :contract_type_cast_or_deploy?, <<~PATTERN
    (send nil? $#available_contract? $...)
  PATTERN
  
  def_node_matcher :contract_type_cast_and_call?, <<~PATTERN
    (send (send nil? $#available_contract? ...) $...)
  PATTERN
  
  def_node_matcher :internal_method_call?, <<~PATTERN
    (send nil? $#internal_method? ...)
  PATTERN
  
  def_node_matcher :lvar_call?, <<~PATTERN
    (send (lvar $_) $_ ...)
  PATTERN
  
  def_node_matcher :direct_state_access?, <<~PATTERN
    (send (send nil? :s) $#state_variable_name?)
  PATTERN
  
  def_node_matcher :state_property_assignment?, <<~PATTERN
    (send
      (send nil? :s)
      $#setter_method?
      $_)
  PATTERN
  
  # TODO array nodes

  # TODO: get real list of events
  def_node_matcher :event_emission?, <<~PATTERN
    (send nil? :emit (sym $_) $(hash ...)?)
  PATTERN
  
  def_node_matcher :require_call?, <<~PATTERN
    (send nil? :require _ _)
  PATTERN
  # TODO: something to disallow blocks
  def_node_matcher :type_cast?, <<~PATTERN
    (send nil? $#castable_type? $_)
  PATTERN
  
  def global_call?(node)
    pattern = '(send (send nil? $_global) $_method)'
    global, method = node.matches?(pattern)
  
    return false unless global && method
  
    global_sym = global.to_sym
    method_sym = method.to_sym
    
    if TransactionContext::STRUCT_DETAILS.key?(global_sym)
      attributes = TransactionContext::STRUCT_DETAILS[global_sym][:attributes]
      attributes.key?(method_sym)
    else
      false
    end
  end
  
  def internal_method?(method_name)
    contract.calculated_functions.map(&:name).include?(method_name) ||
    state_variable_name?(method_name)
  end
  
  def available_contract?(method_name)
    calculated_available_contracts.map(&:name).include?(method_name)
  end
  
  def parent_contract?(contract_name)
    contract.parent_contracts.map(&:name).include?(contract_name)
  end
  
  def contract_reference?(node)
    contract_type_cast_or_deploy?(node) ||
    contract_type_cast_and_call?(node)
  end
  
  def castable_type?(type)
    (8..256).step(8).flat_map{|i| ["uint#{i}", "int#{i}"]}.include?(type.to_s) ||
    [:string, :address, :bytes32].include?(type)
  end
  
  def for_loop_condition?(node)
    node == s(:send, nil, :lambda) &&
    node.each_ancestor(:send).first.matches?("(send nil? :forLoop ...)")
  end
  
  def global_call_unit?(node)
    return true if global_call?(node) 
    return true if json_global_call?(node)
    
    encodePacked = '(send (send nil? :abi) :encodePacked ...)'
    
    return true if node.matches?(encodePacked) ||
                  (node.matches?('(send nil? :abi)') && node.parent.matches?(encodePacked))

    node.matches?("(send nil? $_global_method?)") do |global|
      TransactionContext::STRUCT_DETAILS.key?(global) &&
      global_call?(node.parent)
    end
  end
  
  def json_global_call?(node)
    stringify_call = '(send (send nil? :json) :stringify ...)'
    
    node.matches?(stringify_call) ||
    (node.matches?('(send nil? :json)') && node.parent.matches?(stringify_call))
  end
  
  def check_state_var_assignment(node)
    return state_property_assignment?(node) ||
      (node == s(:send, nil, :s) && state_property_assignment?(node.parent))
  end
  
  def struct_fields
    contract.struct_definitions.flat_map(&:fields).flat_map(&:keys)
  end
  
  def function_arg?(method_name)
    arguments.keys.include?(method_name)
  end
  
  def setter_method?(method_name)
    method_name.to_s.end_with?('=') &&
    state_variable_name?(method_name)
  end
  
  def state_variable_name?(method_name)
    calculated_state_variables.map(&:name).include?(method_name) ||
    calculated_state_variables.map(&:name).include?(method_name.to_s.chomp("=").to_sym)
  end
  
  def check_state_access(node)
    node.each_node(:send) do |send_node|
      return true if direct_state_access?(send_node)
      return true if send_node == s(:send, nil, :s) && direct_state_access?(send_node.parent)
      
      intermediate_allowed = allowed_state_access_methods?(send_node.method_name)
      
      return false unless intermediate_allowed
    end
    
    false
  end
  
  def check_arg_access(node)
    node.each_node(:send) do |send_node|
      return true if function_arg_reference?(send_node)
      intermediate_allowed = allowed_state_access_methods?(send_node.method_name)
      
      return false unless intermediate_allowed
    end
    
    false
  end
  
  def allowed_state_access_methods?(method_name)
    [:[], :[]=, :push, :last, :pop].include?(method_name) ||
    struct_fields.include?(method_name.to_s.chomp("=").to_sym)
  end
  
  def known_sends(node = body)
    node.each_node(:send).select do |send_node|
      known_send?(send_node)
    end
  end
  
  def unknown_sends(node = body)
    node.each_node(:send).to_a - known_sends(node)
  end
  
  def process!
    validate!
  end
  
  def validate!
    if unknown_sends.present?
      raise InvalidFunctionBody, "Unknown function call(s): #{contract.name}: #{unknown_sends.map(&:unparse).join(', ')}"
    end
    
    body.each_node(:const) do |const_node|
      if const_node.namespace.present? ||
        const_node.absolute? ||
        (contract.struct_definitions.exclude?(const_node.short_name) &&
        calculated_available_contracts.map(&:name).exclude?(const_node.short_name)
      )
        
      raise InvalidFunctionBody, "Invalid constant access: #{contract.name}: #{const_node.unparse}"
      end
    end
    
    true
  end
  
  def node_tally
    body.each_node.reject do |node|
      node.type == :send
    end
  end
  
  def misc_known_method?(method_name)
    %i[
      length
      toString
      this
      call
      currentInitCodeHash
      upgradeImplementation
      sqrt
      cast
      blockhash
      keccak256
      new
      array
      create2_address
      ether
      upcase
      base64Decode
      forLoop
      to_i
      []
    ].include?(method_name)
  end
  
  def known_send?(send_node)
    check_state_access(send_node) ||
    check_state_var_assignment(send_node) ||
    check_arg_access(send_node) ||
    event_emission?(send_node) ||
    global_call_unit?(send_node) ||
    require_call?(send_node) ||
    type_cast?(send_node) ||
    misc_known_method?(send_node.method_name) ||
    contract_reference?(send_node) ||
    for_loop_condition?(send_node) ||
    lvar_call?(send_node) ||
    call_to_function_arg?(send_node) ||
    internal_method_call?(send_node) ||
    call_to_parent_contract?(send_node) ||
    BASIC_METHODS.include?(send_node.method_name)
  end
  
  def self.a
    
    paths = [
      # Rails.root.join('spec', 'fixtures', '*.rubidity'),
      Rails.root.join('app', 'models', 'contracts', '*.rubidity')
    ]
    
    files = paths.flat_map { |path| Dir.glob(path) }.reverse
    
    return files.flat_map do |file|
      ParsedContractFile.new(file).contracts.flat_map do |contract|
        # next if contract.name == :NameRegistryRenderer01

        contract.functions.map do |function|
          function.validate!
        end
      end
    rescue InvalidFunctionBody => e
      puts e.message
    end
    
    return files.flat_map do |file|
      ParsedContractFile.new(file).contracts.flat_map do |contract|
        contract.functions.map do |function|
          function.return_type
        end
      end
    end.flatten.compact
    
    file = Rails.root.join('app', 'models', 'contracts', 'FacetSwapV1Pair02.rubidity').to_s
    
    files = paths.flat_map { |path| Dir.glob(path) }.reverse
    
    files.flat_map do |file|
      ParsedContractFile.new(file).contracts.flat_map do |contract|
        contract.functions.map do |function|
          function.node_tally.group_by(&:type)
        end
      end
    end.reduce({}) do |acc, tally|
      tally.each do |type, nodes|
        acc[type] ||= []
        acc[type] += nodes
      end
      acc
    end.flatten.compact
  end
  
  def initialize(**kwargs)
    kwargs.each do |key, value|
      self.public_send("#{key}=", value)
    end
  end
  
  private
  
  def s(type, *children)
    RuboCop::AST::Node.new(type, children)
  end
end
