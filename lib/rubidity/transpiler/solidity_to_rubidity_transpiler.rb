class SolidityToRubidityTranspiler
  attr_accessor :contracts, :primary_contract_name

  def initialize(filename_or_solidity_code, primary_contract_name)
    if File.exist?(filename_or_solidity_code)
      @solidity_file = filename_or_solidity_code
      @solidity_code = nil
    else
      @solidity_code = filename_or_solidity_code
      @solidity_file = nil
    end
    @contracts = {}
    @primary_contract_name = primary_contract_name
    @current_contract = nil
  end

  def get_solidity_ast
    if @solidity_file
      compile_solidity(@solidity_file)
    else
      Tempfile.open(['temp_contract', '.sol']) do |file|
        file.write(@solidity_code)
        file.flush
        compile_solidity(file.path)
      end
    end
  end

  def compile_solidity(file_path)
    stdout, stderr, status = Open3.capture3("solc --ast-compact-json #{file_path}")
    raise "Error running solc: #{stderr}" unless status.success?
  
    # Split the output on lines that contain the delimiter "======="
    sections = stdout.split(/^=======.*=======\n/)
  
    # Filter out any non-JSON sections and parse the JSON
    json_outputs = sections.map do |section|
      begin
        JSON.parse(section)
      rescue JSON::ParserError
        nil # Ignore sections that cannot be parsed as JSON
      end
    end.compact
  
    # Now json_outputs contains all parsed JSON objects
    json_outputs
  end
  
  def transpile
    solidity_asts = get_solidity_ast  # This now returns an array of ASTs
    
    solidity_asts.each do |solidity_ast|
      collect_contracts_and_dependencies(solidity_ast)
    end
    
    primary_contract = @contracts.values.find { |c| c['name'] == @primary_contract_name }
    linearized_base_contracts = primary_contract['linearizedBaseContracts']
    
    ordered_output_contracts = linearized_base_contracts.map do |id|
      @contracts[id]
    end.reverse
    # binding.irb
    rubidity_codes = ordered_output_contracts.map do |solidity_ast|
      collect_declarations(solidity_ast)
      @contracts = @contracts.deep_with_indifferent_access
      @top_level_node = solidity_ast
      rubidity_ast = process(solidity_ast)
      Unparser.unparse(rubidity_ast)
      # ap s(:begin, *Array(rubidity_ast).flatten.compact)
      # Unparser.unparse(s(:begin, *Array(rubidity_ast).flatten.compact))
    end
    rubidity_codes.join("\n\n")  # Join all generated Rubidity code with a newline in between
  end
  
  def collect_contracts_and_dependencies(node)
    traverse_contracts(node)
  end

  def traverse_contracts(node)
    return unless node.is_a?(Hash) && node['nodeType']

    case node['nodeType']
    when 'SourceUnit'
      node['nodes'].each { |child| traverse_contracts(child) }
    when 'ContractDefinition'
      @contracts[node['id']] = node
      node['nodes'].each { |child| traverse_contracts(child) }
    end
  end

  def get_contract_with_dependencies(contract_id)
    contract = @contracts[contract_id]
    linearized_ids = contract[:linearized_base_contracts]
    linearized_ids.map { |id| @contracts[id][:name] }
  end

  def print_contract_and_dependencies(contract_name)
    contract = @contracts.values.find { |c| c[:name] == contract_name }
    raise "Contract #{contract_name} not found" unless contract

    linearized_contract_names = get_contract_with_dependencies(contract[:node]['id'])
    rubidity_codes = linearized_contract_names.map do |name|
      contract_node = @contracts.values.find { |c| c[:name] == name }[:node]
      rubidity_ast = process(contract_node)
      Unparser.unparse(s(:begin, *Array(rubidity_ast).flatten.compact))
    end

    puts rubidity_codes.join("\n\n")  # Join all generated Rubidity code with a newline in between
  end

  def collect_declarations(node)
    return unless node.is_a?(Hash) && node['nodeType']
    # ap @current_contract
    # ap node['nodeType']
    
    ignore_nodes = [
      'ImportDirective',
      'PragmaDirective',
      'StructuredDocumentation',
      'ErrorDefinition',
      'ModifierDefinition',
      'ExpressionStatement'
    ]
    
    case node['nodeType']
    when 'ContractDefinition'
      with_current_contract(node) do
        @contracts[@current_contract] = { functions: {}, variables: {}, events: {}, base_contracts: [], linearized_base_contracts: node['linearizedBaseContracts'] }
        
        if node['baseContracts']
          node['baseContracts'].each do |base_contract|
            base_contract_name = base_contract['baseName']['namePath']
            @contracts[@current_contract][:base_contracts] << base_contract_name
          end
        end
        
        node['nodes'].each { |child| collect_declarations(child) }
      end
    when 'FunctionDefinition'
      ensure_current_contract_set
      func_name = node['name']
      @contracts[@current_contract][:functions][func_name] = node
      if node['body'] && node['body']['nodeType'] == 'Block'
        node['body']['statements'].each { |stmt| collect_declarations(stmt) }
      end
    when 'VariableDeclaration'
      ensure_current_contract_set
      var_name = node['name']
      var_type = node['typeDescriptions']['typeString']
      var_storage = node['stateVariable'] ? 'storage' : 'memory'
      
      @contracts[@current_contract][:variables][node['id']] = {
        type: var_type,
        storage: var_storage,
        id: node['id'],
        name: var_name,
        node: node
      }
    when 'EventDefinition'
      ensure_current_contract_set
      event_name = node['name']
      @contracts[@current_contract][:events][event_name] = node
    else
      if node['nodes']
        node['nodes'].each { |child| collect_declarations(child) }
      end
    end
    

  end

  def ensure_current_contract_set
    raise "No current contract set" unless @current_contract
  end

  def process(node)
    # ap node['nodeType']
    return nil unless node.is_a?(Hash) && node['nodeType']
    method_name = "on_#{node['nodeType'].underscore}"
    if respond_to?(method_name, true)
      send(method_name, node)
    else
      ap node
      raise
    end
  end

  private

  def on_import_directive(node)
    # ignore
  end
  
  def on_if_statement(node)
    condition = process(node['condition'])
    true_body = process(node['trueBody'])
    false_body = process(node['falseBody'])

    if false_body
      s(:if, condition, true_body, false_body)
    else
      s(:if, condition, true_body, nil)
    end
  end

  def on_binary_operation(node)
    left = process(node['leftExpression'])
    right = process(node['rightExpression'])
    operator = case node['operator']
               when '==' then :==
               when '!=' then :!=
               when '>' then :>
               when '<' then :<
               when '>=' then :>=
               when '<=' then :<=
               else raise "Unsupported binary operator: #{node['operator']}"
               end
    s(:send, left, operator, right)
  end
  
  def on_error_definition(node)

  end
  
  def on_structured_documentation(node)

  end
  
  def on_pragma_directive(node)

  end
  
  def on_source_unit(node)
    node['nodes'].map { |child| process(child) }
  end

  def with_current_contract(node)
    old_current_contract = @current_contract
    @current_contract = node['name']
    yield
  ensure
    @current_contract = old_current_contract
  end
  
  def on_contract_definition(node)
    class_name = node['name'].to_sym
    base_contracts = node['baseContracts'].map do |base|
      s(:sym, base['baseName']['name'].to_sym)
    end
    
    body = node['nodes'].map { |child| process(child) }.compact.flatten
  
    s(:block,
      s(:send, nil, :contract, s(:sym, class_name), s(:kwargs, s(:pair, s(:sym, :is), s(:array, *base_contracts)))),
      s(:args),
      s(:begin, *body)
    )
  end

  def on_event_definition(node)
    event_name = node['name']
    params = node['parameters']['parameters'].map do |param|
      s(:pair, s(:sym, param['name'].to_sym), s(:sym, param['typeDescriptions']['typeString'].to_sym))
    end
    s(:send, nil, :event, s(:sym, event_name.to_sym), s(:hash, *params))
  end

  def on_variable_declaration(node)
    type = node['typeDescriptions']['typeString']
    visibility = node['visibility'].to_sym
    name = node['name'].to_sym
  
    if node['typeName']['nodeType'] == 'Mapping'
      mapping_structure = parse_mapping(node['typeName'])
      s(:send, nil, :mapping, mapping_structure, s(:sym, visibility), s(:sym, name))
    elsif node['stateVariable']
      s(:send, nil, type.to_sym, s(:sym, visibility), s(:sym, name))
    else
      on_identifier(node)
    end
  end
  

  def parse_mapping(node)
    key_type = node['keyType']['typeDescriptions']['typeString'].to_sym
    value_type_node = node['valueType']
  
    value_type =
      if value_type_node['nodeType'] == 'Mapping'
        s(:send, nil, :mapping, parse_mapping(value_type_node))
      else
        s(:sym, value_type_node['typeDescriptions']['typeString'].to_sym)
      end
  
    s(:hash, s(:pair, s(:sym, key_type), value_type))
  end
  
  
  def on_function_definition(node)
    function_name = (node['name'].presence || "constructor").to_sym
    params = node['parameters']['parameters'].map do |param|
      s(:pair, s(:sym, param['name'].to_sym), s(:sym, param['typeDescriptions']['typeString'].to_sym))
    end
    visibility = node['visibility'].to_sym
  
    # Process base constructor calls (modifiers)
    base_calls = node['modifiers'].map do |modifier|
      base_contract = modifier['modifierName']['name'].to_sym
      base_arguments = modifier['arguments'].map { |arg| process(arg) }
      
      
      # s(:send, nil, :call_base_contract, s(:sym, base_contract), s(:sym, :constructor), s(:array, *base_arguments))
      
      method_name = "__#{base_contract}_#{function_name}__"
      
      s(:send, nil, method_name, *base_arguments)
    end
  
    # Process the body of the constructor
    body = node['body'] ? node['body']['statements'].map { |stmt| process(stmt) }.compact.flatten : []
  
    s(:block,
      s(:send, nil, :function, s(:sym, function_name), s(:hash, *params), s(:sym, visibility)),
      s(:args),
      s(:begin, *base_calls, *body)
    )
  end
  
  
  def process_modifier(mod)
    if mod['kind'] == 'baseConstructorSpecifier'
      base_contract_name = mod['modifierName']['name']
      arguments = mod['arguments'].map { |arg| process(arg) }
      s(:send, nil, :call_base_contract, s(:sym, base_contract_name.to_sym), s(:sym, :constructor), s(:array, *arguments))
    else
      raise "Unsupported modifier kind: #{mod['kind']}"
    end
  end
  
  def on_modifier_invocation(node)
    # ap node
  end

  def on_expression_statement(node)
    process(node['expression'])
  end

  def on_return_statement(node)
    s(:return, process(node['expression']))
  end

  def on_assignment(node)
    lhs = process(node['leftHandSide'])
    rhs = process(node['rightHandSide'])
    operator = node['operator']

    lhs_name = lhs.children[0]
    var_info = get_variable_definition(node['leftHandSide'])
    
    unless operator == "="
      rhs = s(:send, lhs, operator[0], rhs)
    end
    
    if lhs.type == :send && lhs.children[1] == :storage_get
      s(:send, nil, :storage_set, lhs.children[2], rhs)
    elsif var_info['stateVariable']
      lhs = s(:send, nil, :storage_set, s(:str, var_info['name']), rhs)
    else
      s(:lvasgn, lhs.children[0], rhs)
    end
  rescue => e
    binding.irb
  end

  def on_index_access(node)
    base = process(node['baseExpression'])
    index = process(node['indexExpression'])
    
    if base.type == :send && base.children[1] == :storage_get
      return s(:send, nil, :storage_get, s(:array, *base.children[2], index))
    end
    
    var = get_variable_definition(node['baseExpression'])
    node_type = var['typeName']['nodeType']
    
    if node_type == 'Mapping' && var['stateVariable']
      s(:send, nil, :storage_get, s(:array, s(:str, base.children[0]), index))
    elsif node_type =="ArrayTypeName"
      if var['stateVariable']
        raise
      else
        s(:send, base, :[], index)
      end
    end
  rescue => e
    binding.irb
  end
  
  def get_variable_definition(node)
    ref_id = node['referencedDeclaration']
    find_node_by_id(@top_level_node, ref_id)
  rescue => e
    binding.irb
    raise
  end

  def find_node_by_id(node, ref_id)
    return node if node.is_a?(Hash) && node['id'] == ref_id

    if node.is_a?(Hash)
      node.each_value do |value|
        if value.is_a?(Array)
          value.each do |child|
            found_node = find_node_by_id(child, ref_id)
            return found_node if found_node
          end
        elsif value.is_a?(Hash)
          found_node = find_node_by_id(value, ref_id)
          return found_node if found_node
        end
      end
    end
    
    nil
  end

  def on_member_access(node)
    base = process(node['expression'])
    member = node['memberName'].to_sym
    s(:send, base, member)
  end

  def on_emit_statement(node)
    event_call = process(node['eventCall'])
    
    event_name = event_call.children[1]
    arguments = event_call.children[2]
    
    _, event_name, *args = event_call.children
    
    s(:send, nil, :emit_event, s(:sym, event_name), s(:array, *args))
  end

  def on_function_call(node)
    expression = process(node['expression'])
    
    if type_conversion?(node)
      type_name = node['expression']['typeName']['name']
      arguments = node['arguments'].map { |arg| process(arg) }
      s(:send, nil, :convert_type, s(:sym, type_name.to_sym), *arguments)
    elsif expression.type == :send && expression.children[1] == :super
      # Handle super calls
      base_contract_method_call(expression, node['arguments'])
    else
      arguments = node['arguments'].map { |arg| process(arg) }
      s(:send, nil, expression.children[0], *arguments)
    end
  end
  
  def type_conversion?(node)
    node['nodeType'] == 'FunctionCall' && node['expression']['nodeType'] == 'ElementaryTypeNameExpression'
  end

  def base_contract_method_call(expression, arguments)
    method_name = expression.children[2]
    # Find the immediate base contract implementing this method
    base_contract = find_base_contract_with_method(@current_contract, method_name)
    if base_contract
      base_contract_name = base_contract[:contract_name]
      args = arguments.map { |arg| process(arg) }
      s(:send, s(:const, nil, base_contract_name.to_sym), method_name, *args)
    else
      raise "Unable to find base contract for super call to #{method_name}"
    end
  end

  def find_base_contract_with_method(contract_name, method_name)
    contract = @contracts[contract_name]
    return nil unless contract

    contract[:linearized_base_contracts].each do |base_contract_id|
      base_contract = @contracts.values.find { |c| c[:id] == base_contract_id }
      next unless base_contract
      return { contract_name: base_contract[:name] } if base_contract[:functions].key?(method_name.to_s)
    end
    nil
  end

  def on_return(node)
    value = process(node['expression']) if node['expression']
    s(:return, value)
  end

  def on_binary_operation(node)
    left = process(node['leftExpression'])
    right = process(node['rightExpression'])
    operator = node['operator'].to_sym
    s(:send, left, operator, right)
  end

  def on_identifier(node)
    # binding.irb
    var_info = get_variable_definition(node)
    # binding.irb
    if var_info && var_info[:storage] == 'storage'
      if var_info['node']['typeName']['nodeType'] == 'Mapping'
        s(:lvar, var_info[:name])
      else
        s(:send, nil, :storage_get, s(:array, s(:str, var_info[:name].to_s)))
      end
    else
      s(:lvar, node['name'].to_sym)
    end
  # rescue => e
  #   binding.irb
  end

  def on_unary_operation(node)
    sub_expr = process(node['subExpression'])
    operator = node['operator']
    case operator
    when '++'
      s(:op_asgn, sub_expr, :+, s(:int, 1))
    when '--'
      s(:op_asgn, sub_expr, :-, s(:int, 1))
    else
      raise "Unsupported unary operator: #{operator}"
    end
  end

  def on_for_statement(node)
    init = process(node['initializationExpression'])
    condition = process(node['condition'])
    loop_expr = process(node['loopExpression'])
    body = process(node['body'])
  
    loop_iterator = extract_loop_iterator(node['initializationExpression'])
  
    s(:send, nil, :forLoop,
      s(:block, s(:send, nil, :lambda), s(:args), *init),
      s(:block, s(:send, nil, :lambda), s(:args, s(:procarg0, s(:arg, loop_iterator))), condition),
      s(:block, s(:send, nil, :lambda), s(:args, s(:procarg0, s(:arg, loop_iterator))), loop_expr),
      s(:block, s(:send, nil, :lambda), s(:args, s(:procarg0, s(:arg, loop_iterator))), body)
    )
  end
  
  def extract_loop_iterator(initialization_expression)
    declarations = initialization_expression['declarations']
    if declarations && !declarations.empty?
      declarations.first['name'].to_sym
    else
      raise "Unable to determine loop iterator variable"
    end
  end
  
  def on_literal(node)
    case node['kind']
    when 'number'
      s(:int, node['value'].to_i)
    when 'string', 'literal_string'
      s(:str, node['value'])
    when 'bool'
      node['value'] == 'true' ? s(:true) : s(:false)
    else
      raise "Unsupported literal type: #{node['kind']}"
    end
  end

  def on_variable_declaration_statement(node)
    declarations = node['declarations'].map { |decl| process(decl) }
    initial_value = process(node['initialValue']) if node['initialValue']
    if initial_value
      declarations.map { |decl| s(:lvasgn, decl.children[0], initial_value) }
    else
      declarations
    end
  end

  def on_elementary_type_name_expression(node)
    s(:const, nil, node['typeName']['name'].to_sym)
  end
  
  def on_block(node)
    statements = node['statements'].map { |stmt| process(stmt) }.compact
    s(:begin, *statements)
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
end

class Hash
  def deep_with_indifferent_access
    hash = self.with_indifferent_access
    hash.each do |key, value|
      if value.is_a?(Hash)
        hash[key] = value.deep_with_indifferent_access
      elsif value.is_a?(Array)
        hash[key] = value.map { |item| item.is_a?(Hash) ? item.deep_with_indifferent_access : item }
      end
    end
    hash
  end
end