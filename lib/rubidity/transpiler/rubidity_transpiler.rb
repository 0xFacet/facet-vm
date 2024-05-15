class RubidityTranspiler
  extend ContractErrors  
  
  extend Memoist
  
  attr_accessor :filename
  
  class << self
    extend Memoist
    
    def transpile_file(filename)
      new(filename).generate_contract_artifacts
    end
    
    def transpile_and_get(contract_type)
      unless contract_type.include?(" ")
        contract_type, file = contract_type.split(":")
      end
      
      new(file || contract_type).get_desired_artifact(contract_type)
    end
    
    def find_and_transpile(init_code_hash)
      contracts_dir = Rails.root.join('app', 'models', 'contracts')
      Dir.glob("#{contracts_dir}/*.rubidity").each do |file|
        transpiler = new(file)
        artifacts = transpiler.generate_contract_artifacts
        if artifacts.any? { |artifact| artifact.init_code_hash == init_code_hash }
          return transpiler.get_desired_artifact(init_code_hash)
        end
      end
      raise UnknownInitCodeHash.new("No contract found with init code hash: #{init_code_hash.inspect}")
    end
    memoize :find_and_transpile
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
          @code = filename_or_string
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
  
  def pragma_lang_and_version
    # TODO: do statically
    pragma_parser = Class.new(BasicObject) do
      def self.pragma(lang, version)
        [lang, version]
      end
    end
    
    pragma_parser.instance_eval(Unparser.unparse(pragma_node))
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
      ContractAstProcessor.process(contract_ast)
    end
  end
  
  def ast_with_pragma(contract_ast)
    Parser::AST::Node.new(:begin, [pragma_node, *contract_ast.children])
  end
  
  def extract_contract_name(contract_ast)
    contract_ast.children.last.children.first.children.third.children.first
  end
  
  def compute_init_code_hash(ast)
    "0x" + Digest::Keccak256.hexdigest(ast.inspect)
  end
  
  def get_desired_artifact(name_or_init_hash)
    # TODO: Remove before production
    
    desired_artifact = generate_contract_artifacts.detect do |artifact|
      artifact.name.to_s == name_or_init_hash.to_s ||
      artifact.init_code_hash == name_or_init_hash.to_s
    end
    
    desired_artifact ||= generate_contract_artifacts.last
    
    if name_or_init_hash != desired_artifact.init_code_hash && name_or_init_hash =~ /\A0x/
      InitCodeMapping.find_or_create_by!(
        old_init_code_hash: name_or_init_hash,
        new_init_code_hash: desired_artifact.init_code_hash
      )
    end
    
    sub_transpiler = self.class.new(desired_artifact.source_code)
    
    new_artifacts = sub_transpiler.generate_contract_artifacts(validate: false)
  
    references = new_artifacts.reject { |i| i.name == desired_artifact.name }.
      map{|i| i.attributes.slice("name", "init_code_hash", "source_code")}
    
    desired_artifact.references = references
    desired_artifact
  end
  
  def generate_contract_artifacts(validate: true)
    unless contract_names == contract_names.uniq
      duplicated_names = contract_names.group_by(&:itself).select { |_, v| v.size > 1 }.keys
      raise "Duplicate contract names in #{filename}: #{duplicated_names}"
    end
  
    validate_rubidity! if validate
    
    preprocessed_contract_asts.each_with_object([]) do |contract_ast, artifacts|
      contract_ast = ast_with_pragma(contract_ast)

      new_source = contract_ast.unparse
      contract_name = extract_contract_name(contract_ast)
      init_code_hash = compute_init_code_hash(contract_ast)
  
      artifacts << ContractArtifact.new(
        init_code_hash: init_code_hash,
        name: contract_name,
        source_code: new_source,
        pragma_language: pragma_lang_and_version.first,
        pragma_version: pragma_lang_and_version.last
      )
    end
  end
  
  def validate_rubidity!
    ParsedContractFile.process(file_ast)
  end
end
