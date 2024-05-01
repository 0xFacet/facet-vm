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
    # Check if the target is a send node that represents indexing
    if target.type == :send && target.children[1] == :[]
      # Decompose the operation into an explicit form
      process_compound_assignment(target, op, value)
    else
      # Handle other types of operation assignments normally
      node.updated(nil, safe_process_all(node.children))
    end
  end
  
  def process_compound_assignment(target, op, value)
    base, index = target.children[0], target.children[2]
    processed_base = process(base)
    processed_index = process(index)
    processed_value = process(value)
    
    # Fetch the current value at the index
    current_value = s(:send, processed_base, :[], processed_index)
  
    # Apply the operation to the current value with the new value
    new_value = s(:send, current_value, op, processed_value)
  
    # Assign the result back to the index
    s(:send, processed_base, :[]=, processed_index, new_value)
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
