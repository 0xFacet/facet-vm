class RubidityTranspiler
  extend ContractErrors  
  
  extend Memoist
  
  attr_accessor :filename
  
  class << self
    extend Memoist
    
    # def hack_get(name)
    #   transpile_and_get(name)
    # end
    # memoize :hack_get
    
    def transpile_and_get(contract_type, get_hash: false)
      unless contract_type.include?(" ")
        contract_type, file = contract_type.split(":")
      end
      
      instance = new(file || contract_type)
      
      ast = instance.preprocessed_contract_asts.detect do |ast|
        instance.extract_contract_name(ast).to_s == contract_type.to_s
      end
      
      hsh = new(ast).generate_contract_artifact_json
      
      return hsh if get_hash
      
      ContractArtifact.parse_and_store(hsh)
    end
  end
  
  def initialize(filename_or_string)
    TransactionContext.log_call("ContractCreation", "RubidityTranspiler.new") do
      if filename_or_string.is_a?(Parser::AST::Node)
        @file_ast = filename_or_string
      elsif File.exist?(filename_or_string)
        self.filename = filename_or_string
      else
        with_suffix = "#{filename_or_string}.rubidity"
        contracts_path = Rails.root.join('app', 'models', 'contracts', with_suffix)
        if File.exist?(contracts_path)
          self.filename = contracts_path
        else
          # Check if the file exists in "spec/fixtures"
          fixtures_path = Rails.root.join('spec', 'fixtures', with_suffix)
          if File.exist?(fixtures_path)
            self.filename = fixtures_path
          else
            # If the file doesn't exist in any of the directories, treat the input as a code string
            @code = filename_or_string
            TransactionContext.log_call("ContractCreation", "Unparser.parse") do
              @file_ast = Unparser.parse(filename_or_string)
            end
          end
        end
      end
    end
  end
  
  def filename=(filename)
    absolute_path = if filename.to_s.start_with?("./")
      base_dir = File.dirname(filename)
      File.join(base_dir, filename[2..])
    else
      filename
    end
    
    @filename = absolute_path
  end
  
  def file_ast
    if filename
      ImportResolver.process(filename, @code)
    else
      @file_ast
    end
  end
  memoize :file_ast
  
  def pragma_node
    file_ast.children.first
  end
  
  def contract_asts
    contract_nodes = []
    
    file_ast.children.each_with_object([]).with_index do |(node, contract_ary), index|
      next unless node.type == :block
  
      first_child = node.children.first
  
      if first_child.type == :send && first_child.children.second == :contract
        contract_nodes << node
        ast = Parser::AST::Node.new(:begin, contract_nodes.dup)
        contract_ary << ast
      end
    end
  end
  memoize :contract_asts
  
  def contract_names
    contract_asts.map{|i| i.children.last}.map do |node|
      node.children.first.children.third.children.first
    end
  end
  
  def preprocessed_contract_asts
    TransactionContext.log_call("ContractCreation", "ContractAstProcessor.process") do
      contract_asts.map do |contract_ast|
        ContractAstProcessor.process(contract_ast)
      end
    end
  end
  
  def ast_with_pragma(contract_ast)
    Parser::AST::Node.new(:begin, [pragma_node, *contract_ast.children])
  end
  
  def extract_contract_name(contract_ast)
    contract_ast.children.last.children.first.children.third.children.first
  end
  
  def self.s(type, *children)
    Parser::AST::Node.new(type, children)
  end
  delegate :s, to: :class
  
  def self.compute_legacy_init_code_hash(ast)
    with_pragma = legacy_ast(ast)
    
    "0x" + Digest::Keccak256.hexdigest(with_pragma.inspect)
  end
  delegate :compute_legacy_init_code_hash, to: :class
  
  def self.legacy_ast(ast)
    prag_node = s(:send, nil, :pragma,
      s(:sym, :rubidity),
      s(:str, "1.0.0"))
    
    s(:begin, *[prag_node, *ast.children])
  end
  delegate :legacy_ast, to: :class
  
  def process_and_serialize_ast(ast)
    v1 = ConstsToSends.process(ast.unparse, box: false)
    AstSerializer.serialize(Unparser.parse(v1), format: :json)
  end
  
  def legacy_init_code_hash
    self_ast = preprocessed_contract_asts.last
    legacy_init_code_hash = compute_legacy_init_code_hash(self_ast)
  end
  
  def generate_contract_artifact_json
    ensure_unique_names!
    
    self_ast = preprocessed_contract_asts.last
    dependency_asts = preprocessed_contract_asts.first(preprocessed_contract_asts.length - 1)
    
    dep_artifacts = dependency_asts.map do |ast|
      RubidityTranspiler.new(ast).generate_contract_artifact_json
    end
    
     {
      name: extract_contract_name(self_ast),
      ast: process_and_serialize_ast(self_ast.children.last),
      dependencies: dep_artifacts,
      legacy_source_code: legacy_ast(self_ast).unparse,
    }.with_indifferent_access
  end
  
  def extract_dependencies(contract_ast)
    RubidityTranspiler.new(contract_ast).preprocessed_contract_asts.map do |sub_ast|
      extract_contract_name(sub_ast)
    end
  end
  
  def ensure_unique_names!
    unless contract_names == contract_names.uniq
      duplicated_names = contract_names.group_by(&:itself).select { |_, v| v.size > 1 }.keys
      raise "Duplicate contract names in #{filename}: #{duplicated_names}"
    end
  end
  
  def validate_rubidity!
    ParsedContractFile.process(file_ast)
  end
end
