class ContractAstPreprocessor
  include AST::Processor::Mixin
  
  class << self
    extend Memoist

    def process(available_contracts, ast)
      new(available_contracts).process(ast)
    end
    memoize :process
  end
  
  def initialize(available_contracts)
    @available_contracts = available_contracts.map(&:to_sym)
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
  
  def handler_missing(node)
    new_kids = node.children.map do |child|
      if child.is_a?(Parser::AST::Node)
        child.updated(nil, process(child), nil)
      else
        child
      end
    end
    
    node.updated(nil, new_kids, nil)
  end
  
  def on_send(node)
    receiver, method_name, *args = *node
    
    return unless receiver&.type == :const
    
    parent, name = *receiver
    
    unless parent.nil? && @available_contracts.include?(name)
      return
    end
    
    s(:send,
      s(:send,
        s(:self), name), method_name, *args)
  end
end
