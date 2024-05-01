class ConstsToSends
  include AST::Processor::Mixin
  
  def self.process(ast)
    if ast.is_a?(String)
      ast = Unparser.parse(ast)
    end
    
    obj = ConstsToSends.new
    new_ast = obj.process(ast)
    new_ast.unparse
  end
  
  def handler_missing(node)
    node.updated(nil, safe_process_all(node.children))
  end
  
  def on_const(node)
    namespace, name = *node
    
    s(:send,
      s(:self), name)
  end
  
  def on_if(node)
    condition, if_true, if_false = *node

    # Process the condition as needed
    new_condition = s(:send, nil, :__facet_true__, process(condition))

    # Recursively process the true and false branches
    new_if_true = process(if_true) if if_true
    new_if_false = process(if_false) if if_false

    # Create a new 'if' node with the modified condition and branches
    new_node = node.updated(nil, [new_condition, new_if_true, new_if_false])

    new_node
  end
  
  def on_and(node)
    left, right = *node.children
    new_left = process(left)
    new_right = process(right)
    
    # Wrap the logical AND operation in a bool() cast
    s(:send, nil, :bool,
      s(:and,
        s(:send, nil, :__facet_true__, new_left),
        s(:send, nil, :__facet_true__, new_right)
      )
    )
  end
  
  def on_or(node)
    left, right = *node.children
    new_left = process(left)
    new_right = process(right)
    
    # Wrap the logical OR operation in a bool() cast
    s(:send, nil, :bool,
      s(:or,
        s(:send, nil, :__facet_true__, new_left),
        s(:send, nil, :__facet_true__, new_right)
      )
    )
  end
  
  def on_true(node)
    s(:send, nil, :bool,
      s(:true))
  end
  
  def on_false(node)
    s(:send, nil, :bool,
      s(:false))
  end
  
  def on_int(node)
    value = node.children.first
    
    bits = value.bit_length + (value < 0 ? 1 : 0)
    whole_bits = bits / 8
    if bits % 8 != 0
      whole_bits += 1
    end
    
    whole_bits = 1 if whole_bits == 0
    
    # Choose the type based on whether the value is negative or not
    type_prefix = value < 0 ? "int" : "uint"
    name = :"#{type_prefix}#{whole_bits * 8}"
    
    s(:send, nil, name, s(:int, value))
  end
  
  def on_str(node)
    value = node.children.first
    
    s(:send, nil, :string, s(:str, value))
  end
  
  def on_dstr(node)
    # Reduce the children of the `dstr` node into a single concatenated expression
    concat_expr = node.children.reduce(nil) do |acc, child|
      processed_child = process(child)  # Utilize the existing `process` method
  
      # Initialize the accumulator with the first processed child or concatenate the current one
      acc.nil? ? processed_child : s(:send, acc, :+, processed_child)
    end
  
    concat_expr
  end
  
  def on_nil(node)
    s(:send, nil, :null)
  end
  
  def on_return(node)
    if node.children.empty?
      s(:return, s(:send, nil, :null))
    else
      node.updated(nil, safe_process_all(node.children))
    end
  end
  
  def on_op_asgn(node)
    target, op, value = *node.children
  # binding.irb
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
  # ap [base,index,value,op,processed_base,processed_index,processed_value]
    # Fetch the current value at the index
    current_value = s(:send, processed_base, :[], processed_index)
  
    # Apply the operation to the current value with the new value
    new_value = s(:send, current_value, op, processed_value)
  
    # Assign the result back to the index
    s(:send, processed_base, :[]=, processed_index, new_value)
  end

  def on_send(node)
    if node == (s(:send, nil, :pragma,
      s(:sym, :rubidity),
      s(:str, "1.0.0")))
      
      s(:begin)
    elsif node == s(:send,
      s(:send,
        s(:int, 2), :**,
        s(:int, 256)), :-,
      s(:int, 1))
      
      s(:send, nil, :uint256, s(:int, 2 ** 256 - 1))
    else
      method_name = node.children[1]
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
        node.updated(nil, safe_process_all([node.children[0], new_method_name]) + safe_process_all(node.children[2..-1]))
      else
        node.updated(nil, safe_process_all(node.children))
      end
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
