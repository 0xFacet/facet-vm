class ContractAstPreprocessor
  include AST::Processor::Mixin
  
  attr_accessor :available_contracts, :contracts_referenced_by
  
  class << self
    extend Memoist
    
    def process(ast)
      obj = new
      new_ast = obj.process(ast)
      obj.post_process_references(new_ast)
    end

    memoize :process
  end
  
  def initialize
    @available_contracts = []
    
    @contracts_referenced_by = {}.with_indifferent_access
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
  
  def on_block(node)
    new_kids = node.children.map do |child|
      if child.is_a?(Parser::AST::Node)
        if child.type == :send && child.children.second == :contract
          contract_name = child.children[2].children.last
          @available_contracts << contract_name
        end
        
        process(child)
      else
        child
      end
    end
  
    node.updated(nil, new_kids)
  end
  
  def self.get_contract_ast(ast, contract_name)
    return nil unless ast.is_a?(Parser::AST::Node)
  
    if ast.type == :block
      first_child = ast.children.first
      if first_child.type == :send && first_child.children.second == :contract &&
        first_child.children[2].children.last.to_s == contract_name.to_s
        return ast
      end
    end
  
    ast.children.each do |child|
      result = get_contract_ast(child, contract_name)
      return result if result
    end
  
    nil
  end

  def on_send(node)
    receiver, method_name, *args = *node
    
    return node unless receiver&.type == :const
    
    parent, name = *receiver
    
    unless parent.nil? && @available_contracts.include?(name)
      return node
    end
    
    s(:send,
      s(:send,
        s(:self), name), method_name, *args)
  end
  
  def post_process_references(ast)
    @available_contracts.each do |contract_name|
      @contracts_referenced_by[contract_name] = Set.new
      @contracts_referenced_by[contract_name] << contract_name # a contract always references itself
    end

    @available_contracts.each do |contract_name|
      contract_ast = self.class.get_contract_ast(ast, contract_name)
      traverse_for_references(contract_ast, @contracts_referenced_by[contract_name])
    end
    
    to_remove = []
  
    @available_contracts.each.with_index do |contract_name, index|
      later_contracts = @available_contracts.drop(index + 1)
      
      is_referenced_by_later_contract = later_contracts.any? do |later_contract|
        @contracts_referenced_by[later_contract].include?(contract_name)
      end
      
      unless @available_contracts.last == contract_name || is_referenced_by_later_contract
        to_remove << contract_name
      end
    end
    
    s(:begin, *find_unmatched_contracts(ast, to_remove))
  end
  
  def find_unmatched_contracts(ast, names)
    return [] unless ast.is_a?(Parser::AST::Node)
  
    unmatched_contracts = []
  
    if ast.type == :block
      first_child = ast.children.first
      if first_child.type == :send && first_child.children.second == :contract
        contract_name = first_child.children[2].children.last
        unless names.include?(contract_name)
          unmatched_contracts << ast
        end
      end
    end
  
    ast.children.each do |child|
      unmatched_contracts.concat(find_unmatched_contracts(child, names))
    end
  
    unmatched_contracts
  end
  
  def traverse_for_references(ast, referenced_contracts_set)
    return unless ast.is_a?(Parser::AST::Node)
    
    if ast.type == :send
      if ast.children.second == :contract
        kwargs = ast.children.detect{|i| i.is_a?(Parser::AST::Node) && i.type == :kwargs}
        
        return unless kwargs
        
        is = kwargs.children.detect{|c| c.children.include?(s(:sym, :is))}
        
        return unless is
        
        referenced_contracts_set.merge(is.children.second.children)
      end
      
      receiver, method_name, *args = *ast
      
      if @available_contracts.include?(method_name)
        referenced_contracts_set << method_name
      end
    end

    ast.children.each do |child|
      traverse_for_references(child, referenced_contracts_set)
    end
  end
end
