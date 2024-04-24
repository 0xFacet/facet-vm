module RailsConsoleExtensions
  def no_ar_logging
    ActiveRecord::Base::logger.level = 1
  end
  
  def rparse(ruby)
    RuboCop::AST::ProcessedSource.new(ruby, 3.3).ast
  end
  
  def rmatch(source_code_or_node, pattern)
    test_node = if source_code_or_node.is_a?(String)
      RuboCop::AST::ProcessedSource.new(source_code_or_node, RUBY_VERSION.to_f).ast
    else
      source_code_or_node
    end
    
    matcher = RuboCop::NodePattern.new(pattern)
    match_data = matcher.match(test_node)
    
    return unless match_data
  
    block_given? ? yield(*match_data) : match_data
  end
  
  def unparse(node)
    Unparser.unparse(node)
  end
end

if defined?(Rails::Console)
  include RailsConsoleExtensions
end
