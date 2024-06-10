class SolidityToRubidityTranspiler
  def initialize(solidity_code)
    @solidity_code = solidity_code
  end

  def get_solidity_ast
    Tempfile.open(['temp_contract', '.sol']) do |file|
      file.write(@solidity_code)
      file.flush

      stdout, stderr, status = Open3.capture3("solc --ast-compact-json #{file.path}")
      raise "Error running solc: #{stderr}" unless status.success?

      json_output = stdout.sub(/\A.*=======\n/m, '')
      JSON.parse(json_output)
    end
  end

  def transpile
    solidity_ast = get_solidity_ast
    rubidity_ast = process(solidity_ast)
    rubidity_code = Unparser.unparse(s(:begin, *Array(rubidity_ast).flatten.compact))
    rubidity_code
  end

  def process(node)
    return nil unless node.is_a?(Hash) && node['nodeType']
    method_name = "on_#{node['nodeType'].underscore}"
    if respond_to?(method_name, true)
      send(method_name, node)
    else
      raise "Unsupported node type: #{node['nodeType'].underscore}"
    end
  end

  private

  def on_source_unit(node)
    node['nodes'].map { |child| process(child) }
  end

  def on_contract_definition(node)
    class_name = node['name']
    abstract = node['abstract']
    body = node['nodes'].map { |child| process(child) }.compact.flatten
    s(:block,
      s(:send, nil, :contract, s(:sym, class_name.to_sym), s(:hash, s(:pair, s(:sym, :abstract), abstract ? s(:true) : s(:false)))),
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
    type = node['typeDescriptions']['typeString'].to_sym
    visibility = node['visibility'].to_sym
    name = node['name'].to_sym
    s(:send, nil, type, s(:sym, visibility), s(:sym, name))
  end

  def on_function_definition(node)
    function_name = (node['name'].presence || :constructor).to_sym
    params = node['parameters']['parameters'].map do |param|
      s(:pair, s(:sym, param['name'].to_sym), s(:sym, param['typeDescriptions']['typeString'].to_sym))
    end
    visibility = node['visibility'].to_sym
    modifiers = node['modifiers'].map { |mod| s(:sym, mod['modifierName']['name'].to_sym) }
    returns = node['returnParameters']['parameters'].map { |param| s(:sym, param['typeDescriptions']['typeString'].to_sym) }
    body = node['body']['statements'].map { |stmt| process(stmt) }.compact.flatten
    
    s(:block,
      s(:send, nil, :function, s(:sym, function_name), s(:hash, *params), s(:sym, visibility), *modifiers, s(:hash, s(:pair, s(:sym, :returns), s(:array, *returns)))),
      s(:args),
      s(:begin, *body)
    )
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
  
    if operator == "="
      if lhs.type == :send && lhs.children[1] == :[]
        # Handle assignments to arrays or mappings (e.g., allowance[msg.sender][spender] = amount)
        lhs_base, lhs_index = lhs.children[0], lhs.children[2]
        s(:send, lhs_base, :[]=, lhs_index, rhs)
      else
        # Handle simple assignments to local variables
        s(:lvasgn, lhs.children[0], rhs)
      end
    else
      if lhs.type == :send && lhs.children[1] == :[]
        # Handle compound assignments to arrays or mappings (e.g., balanceOf[msg.sender] -= amount)
        lhs_base, lhs_index = lhs.children[0], lhs.children[2]
        current_value = s(:send, lhs_base, :[], lhs_index)
        operation = s(:send, current_value, operator[0].to_sym, rhs)
        s(:send, lhs_base, :[]=, lhs_index, operation)
      else
        # Handle simple compound assignments to local variables
        operator = operator[0].to_sym
        s(:op_asgn, lhs, operator, rhs)
      end
    end
  end
  
  def on_index_access(node)
    base = process(node['baseExpression'])
    index = process(node['indexExpression'])
    s(:send, base, :[], index)
  end

  def on_member_access(node)
    base = process(node['expression'])
    member = node['memberName'].to_sym
    s(:send, base, member)
  end

  def on_emit_statement(node)
    event_call = process(node['eventCall'])
    s(:send, nil, :emit, event_call)
  end

  def on_function_call(node)
    expression = process(node['expression'])
    arguments = node['arguments'].map { |arg| process(arg) }
    s(:send, expression, :call, *arguments)
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
    s(:lvar, node['name'].to_sym)
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
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
  def on_variable_declaration_statement(node)
    declarations = node['declarations'].map { |decl| process(decl) }
    initial_value = process(node['initialValue']) if node['initialValue']
    if initial_value
      declarations.map { |decl| s(:lvasgn, decl.children[1], initial_value) }
    else
      declarations
    end
  end

  def on_elementary_type_name_expression(node)
    s(:const, nil, node['typeName']['name'].to_sym)
  end
end
