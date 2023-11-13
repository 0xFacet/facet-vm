class RubidityTranspiler
  extend Memoist
  
  attr_accessor :filename
  
  class << self
    def transpile_multiple(files)
      if files.is_a?(String) && File.directory?(files)
        files = Dir.glob(File.join(files, "*.rubidity"))
      end
      
      artifacts = Array.wrap(files).map do |file|
        file = Rails.root.join(file) unless File.exist?(file)
        transpile_file(file)
      end
      
      artifacts.flatten
    end
    
    def transpile_file(filename)
      new(filename).generate_contract_artifacts
    end
    
    def transpile_code_string(string)
      new(string).generate_contract_artifacts
    end
    
    def transpile_and_get(contract_type)
      contract_type, file = contract_type.split(":")
      
      transpiled = RubidityTranspiler.transpile_file(file || contract_type)
      transpiled.detect{|i| i.name.to_s == contract_type}
    end
  end
  
  def initialize(filename_or_string)
    if File.exist?(filename_or_string)
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
          @file_ast = Unparser.parse(filename_or_string)
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
    @file_ast || ImportResolver.process(filename)
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
    contract_asts.map do |contract_ast|
      ContractAstPreprocessor.process(contract_ast)
    end
  end
  
  def ast_with_pragma(contract_ast)
    Parser::AST::Node.new(:begin, [pragma_node, *contract_ast.children])
  end
  
  def extract_contract_name(contract_ast)
    contract_ast.children.last.children.first.children.third.children.first
  end
  
  def compute_init_code_hash(ast)
    Digest::Keccak256.hexdigest(ast.inspect)
  end
  
  def generate_contract_artifacts
    unless contract_names == contract_names.uniq
      raise "Duplicate contract names in #{filename}: #{contract_names}"
    end
  
    contract_references = {}.with_indifferent_access
    preprocessed_contract_asts.each_with_object([]) do |contract_ast, artifacts|
      new_ast = ast_with_pragma(contract_ast)
      new_source = new_ast.unparse
      contract_name = extract_contract_name(contract_ast)
      init_code_hash = compute_init_code_hash(new_ast)
  
      artifacts << OpenStruct.new({
        init_code_hash: init_code_hash,
        name: contract_name,
        ast: new_ast.inspect,
        source_code: new_source,
        references: contract_references.dup
      })
  
      contract_references[contract_name] = init_code_hash
    end
  end
end
