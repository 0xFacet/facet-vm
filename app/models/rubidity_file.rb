class RubidityFile
  extend Memoist

  attr_accessor :filename
  
  class << self
    def registry
      return @registry if @registry
    
      @registry = {}.with_indifferent_access
      add_to_registry(Dir.glob(Rails.root.join("app/models/contracts/*.rubidity")))
    
      @registry
    end
    
    def add_to_registry(files)
      if files.is_a?(String) && File.directory?(files)
        files = Dir.glob(File.join(files, "*.rubidity"))
      end
      
      Array.wrap(files).each do |file|
        file = Rails.root.join(file) unless File.exist?(file)
        new(file).contract_classes.each do |klass|
          registry[klass.init_code_hash] = klass
        end
      end
      
      registry
    end
    
    def clear_registry
      @registry = nil
    end
    
    def find_by_name(name)
      registry.detect{|k, v| v.name == name}.second
    end
    
    def emphasized_code_exerpt(name:, line_number:)
      before_lines = 5
      after_lines = 5
      
      code = find_by_name(name).source_code
      
      lines = code.split("\n")
      start = [0, line_number - 1 - before_lines].max   # Don't go below the first line
      finish = [lines.count - 1, line_number - 1 + after_lines].min  # Don't exceed total lines
      range = (start..finish)
      
      minimum_indent = lines[range].map { |line| line[/\A */].size }.min
      
      range.each do |i|
        # Indent the line correctly
        indented_line = " " * (lines[i][/\A */].size - minimum_indent)
    
        if i == line_number - 1
          # Add '>' to the emphasized line while keeping the original indentation
          lines[i] = "#{indented_line}> #{lines[i].lstrip}"
        else
          lines[i] = "#{indented_line}  #{lines[i].lstrip}"
        end
      end
    
      lines[range].join("\n")
    end
  end
  
  def initialize(filename)
    @filename = filename
  end
  
  def file_ast
    ImportResolver.process(absolute_path)
  end
  memoize :file_ast
  
  def absolute_path
    if filename.start_with?("./")
      base_dir = File.dirname(filename)
      File.join(base_dir, filename[2..])
    else
      filename
    end
  end
  
  def file_source
    file_ast.unparse
  end
  memoize :file_source
  
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

  def pragma_node
    file_ast.children.first
  end
  
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
  
  def contract_classes
    unless contract_names == contract_names.uniq
      raise "Duplicate contract names in #{filename}: #{contract_names}"
    end
    
    available_contracts = {}.with_indifferent_access

    classes = preprocessed_contract_asts.map do |contract_ast|
      new_ast = Parser::AST::Node.new(:begin, [pragma_node, *contract_ast.children])
      
      new_source = new_ast.unparse
      
      contract_name = contract_ast.children.last.children.first.children.third.children.first
      
      contract_class = ContractBuilder.build_contract_class(
        available_contracts: available_contracts,
        source: new_source,
        filename: contract_name.to_s + " " + normalized_filename,
        line_number: 1,
      )
      
      contract_class.instance_variable_set(:@source_code, new_source)
      contract_class.instance_variable_set(:@source_file, normalized_filename)
      
      contract_class.instance_variable_set(:@creation_code, new_ast.inspect)
      init_code_hash = Digest::Keccak256.hexdigest(new_ast.inspect)
      contract_class.instance_variable_set(:@init_code_hash, init_code_hash)
      
      available_contracts[contract_class.name] = contract_class

      contract_class
    end
  end
  memoize :contract_classes

  def normalized_filename
    filename.split("/").last.sub(/\.rubidity$/, "") + ".rubidity"
  end
end