class ImportResolver
  include AST::Processor::Mixin
  
  attr_accessor :known_pragma, :current_filename, :imported_files

  def initialize(initial_filename)
    @known_pragma = nil
    @current_filename = initial_filename
    @imported_files = Set.new
  end
  
  def self.process(initial_filename)
    obj = new(initial_filename)
    ast = obj.process_file(initial_filename)
    
    new_kids = ast.children.reject do |node|
      next false unless node.type == :send
      
      receiver, method_name, *args = *node
      receiver.nil? && method_name == :import
    end
    
    ast.updated(nil, new_kids, nil)
  end
  
  def compute_path(filename)
    return filename if filename == @current_filename
    
    if filename.start_with?("./")
      base_dir = File.dirname(@current_filename)
      filename = File.join(base_dir, filename[2..])
    elsif filename.start_with?("/")
      filename = Rails.root.join(filename[1..]).to_s
    end
  end
  
  def with_current_filename(filename)
    old = @current_filename
    @current_filename = filename
    yield.tap do
      @current_filename = old
    end
  end

  def process_file(filename)
    filename = compute_path(filename)
    code = IO.read(filename)
    ast = Unparser.parse(code)
    
    return if @imported_files.include?(filename)
    
    @imported_files.add(filename)
    
    with_current_filename(filename) do
      process(ast)
    end
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
      
      return if imported_ast.blank?
      
      check_and_remove_pragma(imported_ast.children)
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
end
