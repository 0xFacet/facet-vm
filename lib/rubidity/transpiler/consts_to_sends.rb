class ConstsToSends
  include AST::Processor::Mixin
  
  def self.process(ast)
    obj = ConstsToSends.new
    new_ast = obj.process(ast)
    new_ast.unparse
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end

  def handler_missing(node)
    new_kids = node.children.map do |child|
      if child.is_a?(Parser::AST::Node)
        process(child)
      else
        child
      end
    end
    
    node.updated(nil, new_kids)
  end
  
  def on_const(node)
    namespace, name = *node
    
    s(:send,
      s(:self), name)
  end

  def on_send(node)
    receiver, method_name, *args = *node
    
    return node unless receiver&.type == :const
    
    parent, name = *receiver
    
    return node unless parent.nil?
    
    s(:send,
      s(:send,
        s(:self), name), method_name, *args)
  end
end
