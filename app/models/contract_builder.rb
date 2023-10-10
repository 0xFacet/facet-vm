class ContractBuilder
  include AST::Processor::Mixin
  
  @unparsed_asts = {}

  class << self
    attr_accessor :unparsed_asts
  end
  
  def self.unparsed_ast(ast)
    @unparsed_asts[ast] ||= Unparser.unparse(ast)
  end
  
  attr_reader :available_contracts, :contracts_source_code,
    :hashed_contracts, :current_file
  
  def initialize(filename = '/Users/tom/Dropbox (Personal)/db-src/ethscriptions-vm-server/app/models/contracts_rubidity/ERC20Receiver.rubidity')
    @available_contracts = {}.with_indifferent_access
    @hashed_contracts = {}.with_indifferent_access
    @contract_asts = []
    
    @current_file = Struct.new(:absolute_path, :filename, :source, :source_hash, :ast).new.tap do |file|
      file.filename = filename
      if filename.start_with?("./")
        base_dir = File.dirname(filename)
        filename = File.join(base_dir, filename[2..])
      end
    
      file.absolute_path = filename
    end
    
    # binding.pry if current_file.absolute_path == './ERC20.rubidity'
    @ast_pipeline = AstPipeline.new(ImportResolver)
    ast = @ast_pipeline.process_file(@current_file.absolute_path)
    
    @current_file.ast = ast
    
    @current_file.source = Unparser.unparse(ast)
    @current_file.source_hash = Digest::SHA256.hexdigest(Unparser.unparse(ast)).first(32)
  end

  def process_file
    extract_contract_definitions_from_ast
    construct_contract_classes
    @available_contracts
    self
  end
  
  def extract_contract_definitions_from_ast
    process_all(@current_file.ast.children)
  end
  
  def on_block(node)
    first_child = node.children.first
    
    if first_child.type == :send && first_child.children.second == :contract
      @contract_asts << node
    end
  end
  
  # def normalize_file_name
  #   @current_file.filename = @current_file.filename.sub(/\.rubidity$/, ".rb")
  # end
  
  def construct_contract_classes
    filename = current_file.filename
    
    @contract_asts.each do |ast|
      builder = Builder.new(available_contracts)

      copy = builder.instance_eval(Unparser.unparse(ast))

      replacer = ContractReplacer.new(copy.linearized_parents.map(&:name))
      new_ast = replacer.process(ast)
      
      line_number = new_ast.loc.line
      
      # source = Unparser.unparse(new_ast)
      source = self.class.unparsed_ast(new_ast)
      
      filename = filename.split("/").last
      filename = filename.sub(/\.rubidity$/, "") + ".rubidity"
      new_klass = builder.instance_eval(source, filename, line_number)

      new_klass.instance_variable_set(:@source_code, source)
      
      @available_contracts[new_klass.name] = new_klass
    end
  end
  
  def output_contracts
    @available_contracts.each.with_object({}) do |(name, klass), hash|
      hash["#{name}-#{current_file.source_hash}"] = klass
    end
  end
  
  class Builder < BasicObject
    def initialize(available_contracts)
      @available_contracts = available_contracts.dup
    end
    
    def contract(name, is: [], abstract: false, &block)
      available_contracts = @available_contracts
      
      implementation_klass = ::Class.new(::ContractImplementation) do
        ::Array.wrap(is).each do |dep|
          unless dep_obj = available_contracts[dep.name]
            raise "Dependency #{dep} is not available."
          end
          
          self.parent_contracts << dep_obj
        end
        self.parent_contracts = self.parent_contracts.uniq
        
        if abstract
          @is_abstract_contract = true
        end
        
        define_singleton_method(:name) do
          name.to_s
        end
      end
      
      implementation_klass.tap do |contract|
        contract.instance_variable_set(
          :@available_contracts,
          @available_contracts.merge(name => contract)
        )
        
        contract.instance_eval(&block)
      end
    end
  end
end
