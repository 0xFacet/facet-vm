class AstPipeline
  BASE_DIR = Rails.root.join("app/models/contracts_rubidity/")
  
  @ast_cache = {}

  class << self
    attr_accessor :ast_cache
  end
  
  def initialize(*processors)
    @processors = processors
  end

  def process_file(filename)
    ast = AstPipeline.parse_file(filename)
    @processors.each do |processor|
      ast = processor.new.process(ast)
    end
    ast
  end

  def self.parse_file(filename)
    filename = filename.start_with?("./") ? File.join(BASE_DIR, filename[2..]) : filename
    
    code = IO.read(filename)
    code_to_ast(code)
  end
  
  def self.code_to_ast(code)
    self.ast_cache[code] ||= Unparser.parse(code)
  end
end

class ImportResolver
  include AST::Processor::Mixin

  @ast_cache = {}

  class << self
    attr_accessor :ast_cache
  end
  
  attr_accessor :known_pragma
  
  # PRAGMA_LANG = :rubidity
  # PRAGMA_VERSION = "1.0.0"

  def initialize
    @known_pragma = nil
  end

  def process_file(filename)
    ast = AstPipeline.parse_file(filename)
    process(ast)
  end
  
  def on_begin(node)
    without_pragma = check_and_remove_pragma(node.children)
    
    new_kids = [@known_pragma] + process_all(without_pragma).flatten
    
    node.updated(nil, new_kids, nil)
  end

  def on_send(node)
    receiver, method_name, *args = *node

    if receiver.nil? && method_name == :import
      import_filename = args.first.children.first
      imported_ast = process_file(import_filename)
      
      check_and_remove_pragma(imported_ast.children)
    else
      node
    end
  end
  
  private
  
  def check_and_remove_pragma(children)
    pragma_node = children.detect { |n| n.type == :send && n.children[1] == :pragma }
    
    if !pragma_node || (pragma_node != children.first)
      raise "Pragma must be first line in file!"
    end
    
    if pragma_node.children[2].children[0] != :rubidity || 
      pragma_node.children[3].children[0] != "1.0.0"
      raise "Wrong version!"
    end
    
    if @known_pragma.nil?
      @known_pragma = pragma_node
    elsif pragma_node.children.last != @known_pragma.children.last
      raise "Mismatched pragma in file!"
    end
    
    new_children = children.reject { |n| n == pragma_node }
  end
  
  def parse_file(filename)
    AstPipeline.parse_file(filename)
    # filename = filename.start_with?("./") ? File.join(AstPipeline::BASE_DIR, filename[2..]) : filename

    # code = IO.read(filename)
    # Unparser.parse(code)
  end
end


# class ImportResolver
#   include AST::Processor::Mixin

#   def process_file(filename)
#     ast = parse_file(filename)
#     processed_ast = process(ast)
#   end
  
#   def on_begin(node)
#     node.updated(nil, process_all(node.children).flatten, nil)
#   end
  
#   def on_send(node)
#     receiver, method_name, *args = *node

#     if receiver.nil? && method_name == :import
#       import_filename = args.first.children.first
#       imported_ast = parse_file(import_filename)

#       imported_ast.children
#     end
#   end
  
#   private
  
#   def parse_file(filename)
#     code = IO.read(filename)
#     Unparser.parse(code)
#   end
# end

# class PragmaNormalizer
#   include AST::Processor::Mixin

#   def on_begin(node)
#     is_pragma = lambda{|n| n.type == :send && n.children[1] == :pragma }
#     first_idx = node.children.index(&is_pragma)
    
#     new_kids = node.children.reject.with_index do |n, idx|
#       is_pragma.call(n) && idx != first_idx
#     end
    
#     node.updated(nil, new_kids, nil)
#   end
# end
