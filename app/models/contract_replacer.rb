class ContractReplacer
  include AST::Processor::Mixin
  
  class << self
    extend Memoist

    def process(parent_contracts, ast)
      new(parent_contracts).process(ast)
    end
    memoize :process
  end
  
  def initialize(parent_contracts)
    @parent_contracts = parent_contracts.map(&:to_sym)
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
  
  def handler_missing(node)
    new_kids = node.children.map do |child|
      if child.respond_to?(:to_ast)
        child.updated(nil, process(child), nil)
      else
        child
      end
    end
    
    node.updated(nil, new_kids.flatten, nil)
  end
  
  def on_send(node)
    receiver, method_name, *args = *node
    
    return node unless receiver&.type == :const
    
    parent, name = *receiver
    
    unless parent.nil? && @parent_contracts.include?(name)
      return node
    end
    
    return s(:send,
            s(:send,
              s(:self), name), method_name, *args)
    
    # s(:send,
    #   s(:send,
    #     s(:send, nil, :this), name), method_name, *args)
  end
end

# parent_contracts = [:ERC20]
# source_code = <<-RUBY
# contract(:AddressArg) {
#   function(:respond, { greeting: :string }, :public) {
#     ERC20.hi
#   }
# }
# RUBY

# ast = Unparser.parse(source_code)
# replacer = ContractReplacer.new(parent_contracts)
# new_ast = replacer.process(ast)
# new_code = Unparser.unparse(new_ast)

# puts new_code