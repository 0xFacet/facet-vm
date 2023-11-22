module UnparserExtensions
  ::Parser::AST::Node.class_eval do
    def unparse
      Unparser.unparse(self)
    end
  end
  
  ::Unparser.class_eval do
    class << self
      extend Memoist
      
      unless method_defined?(:original_unparse)
        alias_method :original_unparse, :unparse
        memoize :original_unparse
        memoize :parse
      end
  
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
end
