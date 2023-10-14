module RubidityInterpreter
  class RubidityInterpreterTypeError < StandardError; end
  
  # class ContractExtractor
  #   include AST::Processor::Mixin

  #   attr_reader :contracts
  
  #   def initialize
  #     @contracts = []
  #   end
  
  #   def on_begin(node)
  #     process_all(node.children)
  #   end
    
  #   def on_block(node)
  #     first_child = node.children.first
  #     if first_child.type == :send && first_child.children.second == :contract
  #       @contracts << node
  #     end
  #   end
  # end
  
  # def self.test_extract_contracts
  #   absolute_path = '/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/models/contracts_rubidity/ERC20Receiver.rubidity'
    
  #   pipeline = AstPipeline.new(ImportResolver, PragmaNormalizer)
  #   ast = pipeline.process_file(absolute_path)
    
  #   extractor = ContractExtractor.new
  #   extractor.process(ast)
  #   contracts = extractor.contracts
  # end
  
  # def self.build_implementation_class_from_code_string(filename, code_string)
  #   Builder.new.instance_eval(code_string, filename + ".rubidity", 1)
  # end
  
  # def self.build_implementation_class_from_file(filename)
  #   filename = filename.sub(/\.rubidity$/, "") + ".rubidity"
    
  #   full_name = Rails.root.join("app/models/contracts_rubidity/", filename)
    
  #   code_string = IO.read(full_name)

  #   builder = Builder.new
  #   builder.instance_eval(code_string, filename, 1)
  #   # contracts = builder.instance_variable_get(:@available_contracts).dup
    
    
  # end
  
  def self.migrate
    Dir.glob(Rails.root.join("app/models/contracts/*.rb")).each do |file_path|
      old_content = File.read(file_path)
      
      contract_segments = old_content.split("class Contracts::")[1..-1] # omitting the first segment as it's empty or contains irrelevant content
      converted_contracts = ["pragma :rubidity, \"1.0.0\""]
  
      contract_segments&.each do |contract_content|
        # Extract class name
        class_name = contract_content.match(/^(\w+)/)[1]
  
        # Extract dependencies
        dependencies = contract_content.scan(/is :(\w+)/).flatten
        
        is_statement = nil
        if dependencies.one?
          is_statement = "is: :#{dependencies.first}"
        elsif dependencies.many?
          is_statement = "is: [#{dependencies.join(', ')}]"
        end
  
        is_abstract = contract_content.match(/\s*abstract$/)
        
        contract_content = contract_content.gsub(/\n.*abstract\n.*/, '')
        abstract_string = is_abstract ? "abstract: true" : nil
  
        modifiers = [
          ":#{class_name}",
          is_statement,
          abstract_string,
        ].compact
        
        contract_content = contract_content.gsub(/^\s*is.*$\n*?/, '')
        new_contract = contract_content.gsub(/^#{class_name}.*$/, "contract #{modifiers.join(', ')} do")
    
        # Add pragma and import statements
        new_contract = dependencies.map { |dep| "import './#{dep}.rubidity'" }.join("\n") + "\n\n" + new_contract
    
        new_contract = new_contract.gsub("\n\n\n", "\n")
        converted_contracts << new_contract.strip
      end
  
      # Write all converted contracts to a single .rubidity file
      new_file_name = File.basename(file_path, ".rb") + ".rubidity"
      new_file_path = Rails.root.join('app/models/contracts_rubidity/', new_file_name)
      
      new_file_path = Rails.root.join('app/models/contracts_rubidity/', "#{contract_segments.first.match(/^(\w+)/)[1]}.rubidity")

      # binding.pry if converted_contracts.length > 1
      File.write(new_file_path, converted_contracts.join("\n\n"))
    end
  end
  
  # def self.build_valid_contracts
  #   files = Dir.glob(Rails.root.join("app/models/contracts_rubidity/*.rubidity"))
    
  #   files.each.with_object({}) do |file, hsh|
  #     begin
  #       contracts = ContractBuilder.new(file).process_file.output_contracts
        
  #       hsh.merge!(contracts) do |key, old_val, new_val|
  #         if old_val && old_val != new_val
  #           raise "Duplicate key detected for #{key}: points to both #{old_val} and #{new_val}"
  #         end
  #         new_val
  #       end
  #     rescue => e
  #       puts e.backtrace
  #       raise e
  #     end
  #   end.with_indifferent_access
  # end
  
  def self.build_valid_contracts
    files = Dir.glob(Rails.root.join("app/models/contracts/*.rubidity"))
    
    map = files.each.with_object({}) do |file, hsh|

      contracts = ContractBuilder.new(file).process_file.output_contracts

      hsh.merge!(contracts) do |key, old_val, new_val|
        if old_val && old_val != new_val
          raise "Duplicate key detected for #{key}: points to both #{old_val} and #{new_val}"
        end
        new_val
      end
    end.with_indifferent_access
  end
  
  def self.add_valid_contracts(new_path)
    new_path = new_path.to_s
    # Determine if the new path is a file or a directory
    if File.directory?(new_path)
      # If it's a directory, get all .rubidity files in it
      new_files = Dir.glob(File.join(new_path, "*.rubidity"))
    else
      # If it's a file, just use it
      new_files = [new_path]
    end
  
    # Get the existing contracts
    # Process each new file
    new_files.each do |file|
      new_contracts = ContractBuilder.new(file).process_file.output_contracts.tap do |c|
        c.instance_variable_set(:@is_main_contract, true)
      end
  
      # Merge the new contracts into the existing contracts
      ContractImplementation::VALID_CONTRACTS.merge!(new_contracts) do |key, old_val, new_val|
        if old_val && old_val != new_val
          raise "Duplicate key detected for #{key}: points to both #{old_val} and #{new_val}"
        end
        new_val
      end
    end
  
    # Return the updated contracts
    ContractImplementation::VALID_CONTRACTS
  end
  
  # def self.normalize_code
  #   file_path = "/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/models/contracts_rubidity/ERC20V2.rubidity"
  
  #   code = File.read(file_path)
  #   tree = Unparser.parse(code)
  
  #   normalized_code = Unparser.unparse(tree)
  
  #   normalized_code
  # end
  
  # class BuilderV2
  #   BASE_DIR = Rails.root.join("app/models/contracts_rubidity")
    
  #   def self.process_rubidity_file(filename = '/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/models/contracts_rubidity/ERC20Receiver.rubidity')
  #     absolute_path = filename.start_with?("./") ? File.join(BASE_DIR, filename[2..]) : filename
  #     # out = ImportProcessor.new.process_file(absolute_path)
      
  #     # PragmaNormalizer.new.process(out)
      
  #     # pipeline = AstPipeline.new(ImportResolver, PragmaNormalizer)
  #     pipeline = AstPipeline.new(ImportResolver)
  #     result_ast = pipeline.process_file(absolute_path)
  #   end
  # end
  
  # class ImportProcessor < AST::Processor
  #   def process_file(filename)
  #     ast = parse_file(filename)
  #     processed_ast = process(ast)
  #     Unparser.unparse(processed_ast)
  #   end
    
  #   def on_send(node)
  #     receiver, method_name, *args = *node
  
  #     if receiver.nil? && method_name == :import
  #       import_filename = args.first.children.first
  #       imported_ast = parse_file(import_filename)
  #       # If it's a :begin node, just return it. Otherwise, wrap it in a :begin node.\
        
  #       pp imported_ast.class
        
  #       imported_ast.type == :begin ? imported_ast : s(:begin, [imported_ast])
  #     else
  #       node
  #     end
  #   end
    
  #   private
    
  #   def parse_file(filename)
  #     code = IO.read(filename)
  #     Parser::CurrentRuby.parse(code)
  #   end
  # end
  
  
  # class BuilderV2
  #   BASE_DIR = Rails.root.join("app/models/contracts_rubidity")
  
  #   def self.process_rubidity_file(filename = '/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/models/contracts_rubidity/ERC20Receiver.rubidity')
  #     absolute_path = filename.start_with?("./") ? File.join(BASE_DIR, filename[2..]) : filename
  #     code = IO.read(absolute_path)
  
  #     out = ImportProcessor.new.get_ast_from_file(filename)
      
  #     out.map{|i| Unparser.unparse(i)}.join("\n")
  #   end
  # end
  
  # class ImportProcessor < AST::Processor
  #   def get_ast_from_file(filename)
  #     code = IO.read(filename)
  #     ast = Unparser.parse(code)
  #     process_all(ast)
  #   end
    
  #   def on_send(node)
  #     receiver, method_name, *args = *node
  
  #     if receiver.nil? && method_name == :import
  #       import_filename = args.first.children.first
  #       imported_ast = get_ast_from_file(import_filename)
  #       Unparser.parse(imported_ast.map{|i| Unparser.unparse(i)}.join("\n"))
  #     else
  #       node
  #     end
  #   end
  
  #   # def on_send(node)
  #   #   receiver, method_name, *args = *node

  #   #   if receiver.nil? && method_name == :import
  #   #     import_filename = node.children[2].children.first

  #   #     imported_code = BuilderV2.process_rubidity_file(import_filename)

  #   #     # node.updated(nil, imported_code)
  #   #     # imported_code
  #   #     AST::Node.new(:begin, [imported_code])
  #   #   else
  #   #     node
  #   #   end
  #   # end
  # end
  
  
  
  # class Builder < BasicObject
  #   def initialize
  #     @available_contracts = {}.with_indifferent_access
  #     @pragma_set = false
  #     define_const_missing_for_instance
  #   end
    
  #   def contract(name, is: [], abstract: false, &block)
  #     unless @pragma_set
  #       raise "You must set a pragma before defining a contract."
  #     end
      
  #     available_contracts = @available_contracts
      
  #     implementation_klass = ::Class.new(::ContractImplementation) do
  #       ::Array.wrap(is).each do |dep|
  #         unless dep_obj = available_contracts[dep.name]
  #           raise "Dependency #{dep} is not available."
  #         end
  #         self.parent_contracts << dep_obj
  #       end
  #       self.parent_contracts = self.parent_contracts.uniq
        
  #       if abstract
  #         @is_abstract_contract = true
  #       end
        
  #       define_singleton_method(:name) do
  #         name.to_s
  #       end
  #     end
      
  #     implementation_klass.instance_variable_set(:@available_contracts, @available_contracts.dup)
      
  #     @available_contracts[name] = implementation_klass

  #     implementation_klass.instance_eval(&block)
      
  #     @available_contracts
  #   end
    
  #   def import(file_path)
  #     base_dir = "app/models/contracts_rubidity/"

  #     absolute_path = file_path.start_with?("./") ? ::File.join(base_dir, file_path[2..]) : file_path
    
  #     content = ::File.read(absolute_path)
  #     instance_eval(content)
  #   end
    
  #   def pragma(lang, version)
  #     if lang != :rubidity
  #       raise "Only rubidity is supported."
  #     end
      
  #     if version != "1.0.0"
  #       raise "Only version 1.0.0 is supported."
  #     end
      
  #     @pragma_set = true
  #   end
    
  #   def define_const_missing_for_instance
  #     available_contracts = @available_contracts

  #     singleton_class = (class << self; class << self; self; end; end)
      
  #     singleton_class.send(:define_method, :const_missing) do |name|
  #       if available_contracts[name] && ::TransactionContext.current_contract
  #         ::TransactionContext.current_contract.implementation.send(name)
  #       else
  #         super(name)
  #       end
  #     end
  #   end
    
    
  #   # def define_const_missing_for_class(klass, current_binding)
  #   #   singleton_class = (class << klass; class << self; self; end; end)
  #   #   singleton_class = (class << klass; self; end)

  #   #   singleton_class.send(:define_method, :const_missing) do |name|
  #   #     if @available_contracts[name]
  #   #       # Use the binding to get the instance of the new class
  #   #       instance = eval('self', current_binding)
  
  #   #       ContractProxy.new(instance, name)
  #   #     else
  #   #       super(name)
  #   #     end
  #   #   end
  #   # end
    

    
    # def self.const_missing(name)
    #   # pp ancestors
    #   pp caller
    #   name.to_sym
    # end
  # end
end


# dummy_code_string = <<-CODE
#   contract PublicMintERC20, is: [ERC20] do
#   # contract PublicMintERC20, is: [ERC20, Ownable] do
#     constructor(name: :string) {
#       ERC20.constructor(name: name, symbol: "symbol", decimals: 18)
#     }
    
#     function :mint, { amount: :uint256 }, :public do
#       _mint(to: msg.sender, amount: amount)
#     end
#   end
# CODE

# Contract.first.get_implementation_from_code_string(dummy_code_string)
