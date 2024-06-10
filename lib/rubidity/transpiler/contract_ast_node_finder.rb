class ContractAstNodeFinder
  include AST::Processor::Mixin
  
  attr_accessor :used_nodes, :method_receivers, :method_names, :non_s_receivers
  
  class << self
    extend Memoist
    
    def process
      paths = [
        Rails.root.join('spec', 'fixtures', '*.rubidity'),
        Rails.root.join('app', 'models', 'contracts', '*.rubidity')
      ]
      
      files = paths.flat_map { |path| Dir.glob(path) }
      
      nodes = []
      method_receivers = []
      method_names = []
      non_s_receivers = []
      top_level_methods = []
      
      files.each do |file|
        # contract = file.split('/').last.split('.').first
        # next if contract == 'TestDuplicateContract'
        # transpiled = RubidityTranspiler.transpile_and_get(contract)
        # ap file
        # asts = RubidityTranspiler.new(file).preprocessed_contract_asts
        asts = [Unparser.parse(IO.read(file))]
        
        asts.each do |ast|
          # ap ast
          processor = new
          processor.process(ast)
          
          nodes += processor.used_nodes
          method_receivers += processor.method_receivers
          method_names += processor.method_names
          non_s_receivers += processor.non_s_receivers
          top_level_methods += ast.children          
        end

        # ast = Unparser.parse(transpiled[:source_code])
        

        # top_level_methods += ast.children.uniq(&:type)
      end
      
      # ap top_level_methods.select{|i| i.type == :block}.map(&:children).map(&:first)#.map(&:type).uniq
      # ap top_level_methods.select{|i| i.type == :block}.map{|i| extract_node_details(i)}#.flatten.uniq{|i| i[:method_name]}
      # ap top_level_methods.map(&:type).uniq
      
      nodes.tally.sort_by(&:second).reverse.to_h
      # top_level_methods.tally.sort_by(&:second).reverse.to_h
      # method_receivers.tally.sort_by(&:second).reverse.to_h
      # nil
    end
    
    def extract_node_details(node, level=0)
      return [] unless node.is_a?(Parser::AST::Node)
  
      node_details = []
      if level == 0 # Top level nodes
        case node.type
        when :def, :defs
          # Extract method definitions with their arguments
          method_name = node.children[1]
          args = node.children[2..-1].flat_map { |arg| extract_args(arg) }
          node_details << { type: node.type, method_name: method_name, args: args }
        when :send
          # Extract top-level method calls and their arguments
          _, method_name, *call_args = node.children
          args = call_args.map { |arg| arg_to_s(arg) }
          node_details << { type: :method_call, method_name: method_name, args: args }
        when :block
          # Handle blocks, particularly for DSL method calls that include blocks
          call_node = node.children.first
          if call_node.type == :send
            _, method_name, *call_args = call_node.children
            args = call_args.map { |arg| arg_to_s(arg) }
            node_details << { type: :block, method_name: method_name, args: args }
          end
        end
      end
  
      # Look into child nodes but do not delve deeper if the current node is top-level
      node.children.each do |child|
        node_details.concat(extract_node_details(child, level + 1)) unless level == 0
      end
  
      node_details
    end
  
    # Helper to extract argument details from method definition nodes
    def extract_args(arg_node)
      return [] unless arg_node.is_a?(Parser::AST::Node)
      if arg_node.type == :args
        arg_node.children.map { |arg| arg.children.first.to_s }
      else
        [] # Expand this to handle other types of arguments if necessary
      end
    end
  
    # Convert arguments in send nodes to string representations
    def arg_to_s(arg)
      case arg.type
      when :sym, :str
        arg.children.first
      else
        arg.to_s # Simple string representation, enhance as needed
      end
    end
  end
  
  def initialize
    @used_nodes = []
    @method_receivers = []
    @method_names = []
    @non_s_receivers = []
  end
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
  
  
  def on_send(node)
    @used_nodes << node.type
    
    receiver, method_name, *args = *node
    
    unless receiver && receiver.type == :send && receiver.children[1] == :s
      # ap({ method: method_name, args: args.map(&:to_s) })
      @non_s_receivers << method_name
    end
    
    # if receiver.is_a?(Parser::AST::Node) && receiver.type == :send
    #   _, _, *receiver_args = *receiver
    #   ap receiver_args.first
    #   if receiver_args == [s(:send, nil, :s)]
    #     ap receiver
    #   end
    # end
    # ap receiver unless receiver.is_a?(Parser::AST::Node)
    # ap receiver.type
    # ap receiver.class
    # ap receiver.is_a?(Parser::AST::Node)
    
    # ap s(:block, node.children).unparse if receiver&.type == :array
    # ap node if receiver&.type == :array
    @method_names << method_name
    if receiver.is_a?(Parser::AST::Node)
      @method_receivers << receiver.type
    else
      @method_receivers << receiver
    end
    # process_all(node.children)
    node
  end
  
  def handler_missing(node)
    @used_nodes << node.type
    
    node.children.each do |child|
      if child.is_a?(Parser::AST::Node)
        process(child)
      end
    end
  end
end
