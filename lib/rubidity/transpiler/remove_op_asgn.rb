class RemoveOpAsgn
  include AST::Processor::Mixin
  
  def self.process(ast)
    if ast.is_a?(String)
      ast = Unparser.parse(ast)
    end
    
    obj = new
    new_ast = obj.process(ast)
    new_ast.unparse
  end
  
  def handler_missing(node)
    node.updated(nil, safe_process_all(node.children))
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
    
    processed_object = process(object)
    processed_index = process(index)
    processed_value = process(value)
    
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
  
  private
  
  def safe_process_all(nodes)
    nodes.to_a.map do |child|
      if child.is_a?(Parser::AST::Node)
        process(child)
      else
        child
      end
    end
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
end
