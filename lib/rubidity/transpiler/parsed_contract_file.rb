class ParsedContractFile
  extend Memoist
  attr_accessor :filename, :file_ast, :pragma
  
  extend RuboCop::AST::NodePattern::Macros
  class InvalidRubidityFile < StandardError; end
  
  class << self
    extend Memoist
    
    def process(ast)
      ParsedContractFile.new(ast).process!
    end

    memoize :process
  end
  
  def_node_matcher :contract_definition?, <<~PATTERN
    (block
      (send nil? :contract 
        (sym $_name)                # Captures the contract's name
        $(hash ...)?)                # Optionally captures a hash with any keyword arguments
      (args)                        # Captures an empty args node
      $_
    )                           # Captures the block content
  PATTERN
  
  def initialize(filename_ast_or_code = nil)
    filename_ast_or_code ||= Rails.root.join('app', 'models', 'contracts', 'FacetSwapV1Callee.rubidity').to_s
    
    self.file_ast = if filename_ast_or_code.is_a?(String)
      if File.exist?(filename_ast_or_code)
        self.filename = filename_ast_or_code
        ast = ImportResolver.process(filename_ast_or_code)
        code = ast.unparse
        
        RuboCop::AST::ProcessedSource.new(code, RUBY_VERSION.to_f).ast
      else
        RuboCop::AST::ProcessedSource.new(filename_ast_or_code, RUBY_VERSION.to_f).ast
      end
    else
      RuboCop::AST::ProcessedSource.new(RemoveOpAsgn.process(filename_ast_or_code), RUBY_VERSION.to_f).ast
    end
  end
  
  def process!
    file_ast.children.each do |node|
      pragma_pattern = "(send nil? :pragma (sym $_language) (str $_version))"
      
      if (language, version = node.matches?(pragma_pattern))
        if pragma.present?
          raise InvalidRubidityFile, "Multiple pragma statements found"
        end
        
        self.pragma = { language: language, version: version }
      elsif !contract_definition?(node)
        raise InvalidRubidityFile, "Invalid top-level statement: #{node.unparse}"
      end
    end
    
    raise InvalidRubidityFile, "No contracts found" if contracts.empty?
    
    unless contracts.map(&:name).sort == contracts.map(&:name).sort.uniq
      raise InvalidRubidityFile, "Duplicate contract names found"
    end
    
    unless pragma == {:language=>:rubidity, :version=>"1.0.0"}
      raise InvalidRubidityFile, "Invalid pragma statement: #{pragma.inspect}"
    end
    
    contracts.reject{|i| i.name.to_s == "ERC20LiquidityPool" || i.name.to_s =='NameRegistryRenderer01'}.each(&:process!)
    
    AstPostProcessor.new(file_ast).process!
    true
  end
  
  def contracts
    available_contracts = []
    
    file_ast.children.map do |node|
      processed = process_contract(node, available_contracts.deep_dup)
      next unless processed
      available_contracts << processed
      processed
    end.compact
  end
  memoize :contracts
  
  def process_contract(node, available_contracts)
    contract_definition?(node) do |name, options_hash, body|
      is = []
      abstract = false
      upgradeable = false
      
      unless body&.type == :begin
        body = s(:begin, *Array.wrap(body).compact)
      end
      
      options_hash = options_hash.first
      
      options_hash&.children&.each do |pair|
        case pair.key.value
        when :is
          is = pair.value.type == :array ? pair.value.children.map(&:value) : [pair.value.value]
        when :abstract
          abstract = pair.value.type == :true
        when :upgradeable
          upgradeable = pair.value.type == :true
        else
          raise "Unknown option #{pair.key.value}"
        end
      end
      
      ParsedContract.new(
        name: name,
        parents: is,
        abstract: abstract,
        upgradeable: upgradeable,
        body: body,
        available_contracts: available_contracts
      )
    end
  end
  memoize :process_contract
  
  private
  
  def s(type, *children)
    RuboCop::AST::Node.new(type, children)
  end
end
