module UnparserExtensions
  unless defined?(::Unparser::DEFAULT_EMIT_INDEX)
    ::Unparser::DEFAULT_EMIT_INDEX = true
  end
    
  ::Parser::AST::Node.class_eval do
    def unparse(emit_index: ::Unparser::DEFAULT_EMIT_INDEX)
      Unparser.unparse(self, emit_index: emit_index)
    end
  end
  
  ::Unparser.class_eval do
    class << self
      extend Memoist
      
      def custom_builder(emit_index: ::Unparser::DEFAULT_EMIT_INDEX)
        Class.new(Parser::Builders::Default) do
          modernize
    
          define_singleton_method(:emit_index) do
            emit_index
          end
          
          def initialize
            super
            self.emit_file_line_as_literals = false
          end
        end
      end
      
      def parser(emit_index: ::Unparser::DEFAULT_EMIT_INDEX)
        Parser::CurrentRuby.new(self.custom_builder(emit_index: emit_index).new).tap do |parser|
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
  
      def unparse(node, emit_index: ::Unparser::DEFAULT_EMIT_INDEX)
        code = original_unparse(node)
        test_node = parse(code, emit_index: emit_index)
  
        unless test_node == node
          raise "Unparse error: #{code}"
        end
        
        code
      end

      def parse(code, emit_index: ::Unparser::DEFAULT_EMIT_INDEX)
        parser(emit_index: emit_index).parse(buffer(code))
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
  
  def unparse(emit_index: ::Unparser::DEFAULT_EMIT_INDEX)
    Unparser.unparse(self, emit_index: emit_index)
  end
end
