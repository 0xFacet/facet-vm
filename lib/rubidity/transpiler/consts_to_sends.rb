class ConstsToSends
  include AST::Processor::Mixin
  
  class << self
    extend Memoist
    
    def process(start_ast)
      if start_ast.is_a?(String)
        ast = Unparser.parse(start_ast, emit_index: false)
      else
        ast = start_ast
      end
   
      NodeChecker.new.process(ast)
      
      obj = ConstsToSends.new
      new_ast = obj.process(ast)
      new_ast.unparse
    end
    memoize :process
  end
  
  def self.box_function_name
    :__box__
  end
  delegate :box_function_name, to: :class
  
  def self.unbox_and_get_bool_function_name
    :__get_bool__
  end
  delegate :unbox_and_get_bool_function_name, to: :class
  
  def handler_missing(node)
    node.updated(nil, safe_process_all(node.children))
  end
  
  SimpleBoxNodes = [:true, :false, :array, :hash, :int, :str, :sym, :lvasgn, :nil, :lvar]

  SimpleBoxNodes.each do |type|
    # TODO: Do we need to box lvasgn?
    
    define_method("on_#{type}") do |node|
      box_expression(node)
    end
  end
  
  def on_const(node)
    namespace, name = *node
    
    if namespace
      raise NodeChecker::NodeNotAllowed, "Namespace not supported: #{node.inspect}"
    end
    
    process(s(:send, s(:self), name))
  end
  
  def on_if(node)
    condition, if_true, if_false = *node

    # Process the condition as needed
    new_condition = unbox_and_get_bool(process(condition))

    # Recursively process the true and false branches
    new_if_true = process(if_true) if if_true
    new_if_false = process(if_false) if if_false

    # Create a new 'if' node with the modified condition and branches
    new_node = node.updated(nil, [new_condition, new_if_true, new_if_false])

    new_node
  end
  
  def on_and(node)
    left, right = *node.children
    process_logical_operation(:and, left, right)
  end
  
  def on_or(node)
    left, right = *node.children
    process_logical_operation(:or, left, right)
  end
  
  def process_logical_operation(operation, left_node, right_node)
    processed_left = process(left_node)
    processed_right = process(right_node)
  
    # Wrap the logical operation in a bool() cast
    box_single(
      s(operation,
        unbox_and_get_bool(processed_left),
        unbox_and_get_bool(processed_right)
      )
    )
  end
  
  def on_self(node)
    raise NodeChecker::NodeNotAllowed "Invalid use of 'self' node: #{node.inspect}"
  end
  
  def on_pair(node)
    left, right = *node.children
    
    unless left.type == :sym
      raise "Unsupported key type for hash pair: #{left.inspect}"
    end
    
    s(:pair, left , process(right))
  end
  
  # def on_begin(node)
  #   if node.children.size == 1
  #     process(node.children.first)
  #   else
  #     node.updated(nil, safe_process_all(node.children))
  #   end
  # end
  
  def on_masgn(node)
    # TODO: doesn't work with mapping assignments
    
    left, right = *node.children
    
    lvars_to_box = []
    
    updated_left_children = left.children.map do |child|
      if child.type == :lvasgn
        lvars_to_box << child
        child
      else
        process(child)
      end
    end
    
    lvar_box_nodes = lvars_to_box.map do |lvar|
      var_name = lvar.children[0]
      var_value = process(s(:lvar, var_name))
      
      process(s(:lvasgn, var_name, var_value))
    end
    
    updated_left = left.updated(nil, updated_left_children)
    
    updated_node = node.updated(nil, [updated_left, process(right)])
    
    s(:begin, updated_node, *lvar_box_nodes)
  end
  
  def on_dstr(node)
    concat_expr = safe_process_all(node.children).reduce(nil) do |acc, child|
      acc.nil? ? child : box_single(s(:send, acc, :+, child))
    end
  
    box_single(concat_expr)
  end
  
  def on_return(node)
    if node.children.empty?
      s(:return, process(s(:nil)))
    else
      node.updated(nil, safe_process_all(node.children))
    end
  end
  
  def on_op_asgn(node)
    target, op, value = *node.children
  
    if target.type == :lvasgn
      process(handle_local_variable_assignment(target, op, value))
    elsif target.type == :send
      process(handle_method_setter_assignment(target, op, value))
    else
      raise "Unsupported target type for compound assignment: #{target.type}"
    end
  end
  
  def handle_local_variable_assignment(target, op, value)
    var_name = target.children.first
    
    # Compute the new value based on the operation
    new_value = s(:send, s(:lvar, var_name), op, process(value))
    
    # Update the AST node to represent the local variable assignment
    s(:lvasgn, var_name, new_value)
  end
  
  def handle_method_setter_assignment(target, op, value)
    object, method_name, index = *target.children
    
    processed_object = safe_process(object)
    processed_index = safe_process(index)
    processed_value = safe_process(value)
    
    current_value = if index
      s(:send, processed_object, method_name, processed_index)
    else
      s(:send, processed_object, method_name)
    end
    
    new_value = s(:send, current_value, op, processed_value) 
    
    if index
      s(:send, processed_object, "#{method_name}=".to_sym, processed_index, new_value)
    else
      s(:send, processed_object, "#{method_name}=".to_sym, new_value)
    end
  end

  SENDS_TO_UNDERSCORE = %w(
    abi.encodePacked
    msg.sender
    block.timestamp
    json.stringify
    tx.origin
    tx.current_transaction_hash
    block.number
    block.timestamp
    block.blockhash
    block.chainid
  ).map { |pattern| pattern.split('.').map(&:to_sym) }.to_set.freeze
  
  def underscore_sends(node)
    receiver, method_name, *args = *node
    
    unless receiver&.type == :send && receiver.children[0].nil?
      return node
    end
    
    receiver_method_name = receiver.children[1]
    
    method_call = [receiver_method_name, method_name]

    if SENDS_TO_UNDERSCORE.include?(method_call)
      new_method_name = "#{method_call[0]}_#{method_call[1]}".to_sym
      
      return process(s(:send, nil, new_method_name, *args))
    end
    
    node
  end
  
  def underscore_const_sends(node)
    receiver, method_name, *args = *node
    
    unless (
      receiver&.type == :const && receiver.children[0].nil?
    ) || (
      receiver&.type == :send && receiver.children[0]&.type == :self
    )
      return node
    end
    
    receiver_name = receiver.children[1]
    
    new_method_name = "__#{receiver_name}_#{method_name}__".to_sym
    
    process(s(:send, nil, new_method_name, *args))
  end
  
  def on_send(node)
    receiver, method_name, *args = *node
    
    if receiver&.type == :sym && method_name == :[] && (args.empty? || args.one? && args.first.type == :int)
      return process(s(:send, nil, :array, receiver, *args))
    end
    
    # Case where processor turns consts to sends before this.
    if receiver&.type == :self && method_name.to_s.match?(/\A[A-Z]/) && args.empty?
      return node.updated(nil, [receiver, method_name])
    end
    
    if is_box_send?(node)
      return node
    end
    
    underscored = underscore_sends(node)
    
    if underscored != node
      return underscored
    end
    
    underscored = underscore_const_sends(node)
    
    if underscored != node
      return underscored
    end
    
    if node == (s(:send, nil, :pragma,
      s(:sym, :rubidity),
      s(:str, "1.0.0")))
      
      process(s(:begin))
    elsif node == s(:send,
      s(:send,
        s(:int, 2), :**,
        s(:int, 256)), :-,
      s(:int, 1))
      
      process(s(:int, 2 ** 256 - 1))
    else
      operator_to_method_name = {
        :== => :eq,
        :> => :gt,
        :<= => :lte,
        :>= => :gte,
        :< => :lt,
        :! => :not,
        :!= => :ne
      }
      
      if operator_to_method_name.keys.include?(method_name)
        new_method_name = operator_to_method_name[method_name]
        
        new_node = node.updated(nil, safe_process_all([node.children[0], new_method_name] + node.children[2..-1]))
        
        box_single(new_node)
      else
        new_node = node.updated(nil, safe_process_all(node.children))
        
        box_single(new_node)
      end
    end
  end
  
  def on_block(node)
    send_node, args, body = *node
    receiver, method_name, *send_args = *send_node
    
    if send_args[0] == s(:sym, :editUpgradeLevel)
      hack_node = s(:if,
        s(:send,
          s(:send,
            s(:send,
              s(:send,
                s(:send, nil, :s), :tokenUpgradeLevelsByCollection), :[],
              s(:send, nil, :collection)), :length), :==,
          s(:int, 0)),
        s(:send,
          s(:send,
            s(:send,
              s(:send, nil, :s), :tokenUpgradeLevelsByCollection), :[],
            s(:send, nil, :collection)), :push,
          s(:send, nil, :TokenUpgradeLevel)), nil)
          
      body = s(:begin, hack_node, body)
    end
    
    processed_body = body ? process(body) : process(s(:nil))
    
    new_send = send_node.updated(nil, safe_process_all(send_node.children))
    
    node.updated(nil, [new_send, process(args), processed_body])
  end
  
  private
  
  def is_box_send?(node)
    node.type == :send && node.children[1] == box_function_name
  end
  
  def box_single(node)
    if is_box_send?(node)
      return node
    end
    
    if node.type == :begin && node.children.size == 1 && is_box_send?(node.children.first)
      return node.children.first
    end
    
    s(:send, nil, box_function_name, node)
  end
  
  def unbox_and_get_bool(node)
    if node.type == :send && node.children[1] == unbox_and_get_bool_function_name
      return node
    end
    
    s(:send, nil, unbox_and_get_bool_function_name, node)
  end
  
  def box_expression(expr)
    if expr.type == :send && expr.children[1] == box_function_name
      return expr
    end
    
    processed_expr = expr.updated(nil, safe_process_all(expr.children))
    
    box_single(processed_expr)
  end
  
  def safe_process(node)
    if node.is_a?(Parser::AST::Node)
      process(node)
    else
      node
    end
  end
  
  def safe_process_all(nodes)
    nodes.to_a.map do |child|
      safe_process(child)
    end
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
end
