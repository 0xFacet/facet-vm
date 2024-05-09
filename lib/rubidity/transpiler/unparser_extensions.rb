module UnparserExtensions
  ::Parser::AST::Node.class_eval do
    def unparse
      Unparser.unparse(self)
    end
  end
  
  ::Unparser.class_eval do
    class << self
      extend Memoist
      
      def custom_builder
        Class.new(Parser::Builders::Default) do
          modernize
    
          def self.emit_index
            false
          end
          
          def initialize
            super
      
            self.emit_file_line_as_literals = false
          end
        end
      end
      
      def parser
        Parser::CurrentRuby.new(self.custom_builder.new).tap do |parser|
          parser.diagnostics.tap do |diagnostics|
            diagnostics.all_errors_are_fatal = true
          end
        end
      end
      
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

::RuboCop::AST::Node.class_eval do
  def matches?(pattern)
    matcher = ::RuboCop::NodePattern.new(pattern)
    match_data = matcher.match(self)
    
    return unless match_data
  
    block_given? ? yield(*match_data) : match_data
  end
  
  def unparse
    Unparser.unparse(self)
  end
end
