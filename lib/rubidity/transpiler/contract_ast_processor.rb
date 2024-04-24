class ContractAstProcessor
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
    return find_matched_contracts(ast, [contract_name]).first
  end

  def post_process_references(ast)
    @available_contracts.each do |contract_name|
      @contracts_referenced_by[contract_name] = Set.new
    end

    @available_contracts.each do |contract_name|
      contract_ast = self.class.get_contract_ast(ast, contract_name)
      traverse_for_references(contract_ast, @contracts_referenced_by[contract_name])
    end
  
    remaining_contracts = @available_contracts.dup
    to_remove = []
  
    loop do
      to_remove.clear
  
      remaining_contracts.each.with_index do |contract_name, index|
        later_contracts = remaining_contracts.drop(index + 1)
  
        is_referenced_by_later_contract = later_contracts.any? do |later_contract|
          @contracts_referenced_by[later_contract].include?(contract_name)
        end
  
        unless remaining_contracts.last == contract_name || is_referenced_by_later_contract
          to_remove << contract_name
        end
      end
      
      break if to_remove.empty?
  
      remaining_contracts -= to_remove
    end
    
    sorted = topological_sort(remaining_contracts)
    final = self.class.find_matched_contracts(ast, sorted)
    
    s(:begin, *final)
  end
  
  def topological_sort(contracts)
    visited = {}
    stack = []
    
    contracts.sort.each do |contract|
      visit(contract, visited, stack, contracts)
    end
    
    stack
  end
  
  def visit(contract, visited, stack, contracts)
    return if visited[contract]
    
    visited[contract] = true
  
    if @contracts_referenced_by[contract]
      sorted_deps = @contracts_referenced_by[contract].to_a.sort
      sorted_deps.each do |dep|
        if !contracts.include?(dep)
          raise "Contract #{contract} references missing contract #{dep}"
        end
        visit(dep, visited, stack, contracts)
      end
    end
    
    stack.push(contract)
  end
  
  def self.find_matched_contracts(ast, names)
    return [] unless ast.is_a?(Parser::AST::Node)
  
    matched_contracts = []
  
    if ast.type == :block
      first_child = ast.children.first
      if first_child.type == :send && first_child.children.second == :contract
        contract_name = first_child.children[2].children.last
        if names.include?(contract_name)
          matched_contracts << ast
        end
      end
    end
  
    ast.children.each do |child|
      matched_contracts.concat(find_matched_contracts(child, names))
    end
  
    matched_contracts.sort_by do |node|
      first_child = node.children.first
      contract_name = first_child.children[2].children.last
      names.index(contract_name)
    end
  end
  
  def traverse_for_references(ast, referenced_contracts_set)
    return unless ast.is_a?(Parser::AST::Node)
    
    if ast.type == :send
      if ast.children.second == :contract
        kwargs = ast.children.detect{|i| i.is_a?(Parser::AST::Node) && i.type == :kwargs}
        
        return unless kwargs
        
        is = kwargs.children.detect{|c| c.children.include?(s(:sym, :is))}
        
        return unless is
        
        is_els = is.children.second.children.map do |el|
          el.respond_to?(:children) ? el.children : el
        end.flatten
        
        referenced_contracts_set.merge(is_els)
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
