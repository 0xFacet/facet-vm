class Parser::AST::Node
  def unparse
    Unparser.safe_unparse(self)
  end
end

module Unparser
  def self.safe_unparse(node)
    code = Unparser.unparse(node)
    test_node = Unparser.parse(code)
    
    unless test_node == node
      raise "Unparse error: #{code}"
    end
    
    code
  end
end
