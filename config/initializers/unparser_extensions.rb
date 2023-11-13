class Parser::AST::Node
  def unparse
    Unparser.unparse(self)
  end
end

module Unparser
  class << self
    extend Memoist
    
    alias_method :original_unparse, :unparse
    memoize :original_unparse
    memoize :parse

    def unparse(node)
      code = original_unparse(node)
      test_node = parse(code)

      unless test_node == node
        raise "Unparse error: #{code}"
      end
      
      code
    end
  end
end
