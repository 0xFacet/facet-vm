class ContractAstValidator
  include AST::Processor::Mixin
  class InvalidSendNode < StandardError; end
  
  class FunctionDefinition
    attr_reader :name, :parameters, :visibility,
    :body_ast, :is_constructor, :valid, :top_level_node
    
    alias_method :params, :parameters
    
    def self.t
      ruby = <<~RUBY
      function(:add) do
      end
      RUBY
      
      ast = Unparser.parse(ruby)
      
      new(ast)
    end
    
    def valid?
      !!@valid
    end
    
    def initialize(node_or_string)
      node = node_or_string.is_a?(String) ? Unparser.parse(node_or_string) : node_or_string
      
      @top_level_node = node
      @valid = parse_node(node)
    end
  
    def s(type, *children)
      Parser::AST::Node.new(type, children)
    end
    
    def parse_node(node)
      if node.type == :send
        node = s(:block, node, s(:args), nil)
      end
      
      return unless node.type == :block &&
      node.children.first(2).map(&:type) == [:send, :args]
  
      send_node, args_node, body_node = node.children
      receiver, method_name, *args = send_node.children
      
      return unless [:function, :constructor].include?(method_name)
      return unless receiver.nil?
      
      return unless args_node.children.empty?
      
      @is_constructor = method_name == :constructor
      @name, @parameters, @visibility = parse_function_header(send_node)
      @body_ast = body_node
      
      return unless @name.present?
      
      true
    end
    
    def parse_function_header(send_node)
      name = @is_constructor ? :constructor : extract_name(send_node.children[2])
      
      params_arg = @is_constructor ? send_node.children[2] : send_node.children[3]
      params = {}
      options = []
      
      params = case params_arg&.type
      when :hash
        parse_params(params_arg)  # For regular hash parameters
      when :kwargs
        parse_kwargs(params_arg)  # For keyword arguments
      when :sym
        options = extract_options(send_node.children[2..-1])  # All following are options, params are {}
        {}
      else
        {}  # Default to empty params if none provided
      end
      
      if params_arg && params_arg.type != :sym
        # Extract options only if params_arg is not a symbol (already handled)
        options += extract_options(send_node.children[3..-1])
      end
    
      visibility = options.find { |opt| [:public, :private, :protected].include?(opt) } || :public
      [name, params, options, visibility]
      
      # if params_arg
      #   if params_arg.type == :hash
      #     params = parse_params(params_arg)
      #     options = extract_options(send_node.children[4..-1])  # All after params are options
      #   elsif params_arg.type == :sym
      #     # Params are empty, treat all following as options
      #     options = extract_options(send_node.children[3..-1])
      #   else
      #     raise "Unexpected parameter node type: #{params_arg.type}"
      #   end
      # end
    
      # visibility = options.find { |opt| [:public, :private, :protected].include?(opt) } || :public
      # [name, params, options, visibility]
    end
    
    def parse_kwargs(kwargs_node)
      kwargs = {}
      kwargs_node.children.each do |pair|
        key = extract_name(pair.children[0])
        type = extract_name(pair.children[1])
        kwargs[key] = type
      end
      kwargs
    end
    
    def parse_params(param_node)
      params = {}
      param_node.children.each do |pair|
        key = extract_name(pair.children[0])
        type = extract_name(pair.children[1])
        params[key] = type
      end
      params
    rescue => e
      ap param_node.unparse  # Debug output in case of an error
      raise e
    end
    
    def extract_options(nodes)
      nodes.map { |node| node.type == :sym ? node.children.last : nil }.compact
    end
    
    def extract_name(node)
      # Considerations for directly resolving symbols or method names
      node.is_a?(Parser::AST::Node) ? node.children.last : node
    end
  end
  
  class << self
    extend Memoist
    
    def d
      ContractAstValidator.validate_all
    end
    
    def test_files
      paths = [
        Rails.root.join('spec', 'fixtures', '*.rubidity'),
        Rails.root.join('app', 'models', 'contracts', '*.rubidity')
      ]
      
      files = paths.flat_map { |path| Dir.glob(path) }
    end
       
    
    def validate_all(
      files = test_files
    )
      names = []
      called = []
      state_vars = []
      
      files.each do |file|
        # asts = RubidityTranspiler.new(file).preprocessed_contract_asts
        asts = [Unparser.parse(IO.read(file))]
        
        asts.each do |ast|
          # ap ast
          validator = new(ast)
          validator.validate_allowed_nodes
          validator.validate_top_level_structure
          validator.validate_contracts
          names += validator.function_names
          called += validator.called_functions
          state_vars += validator.state_variables
        end
      end
      
      state_vars += state_vars.map{|i| (i.to_s + "=").to_sym}
      
      net = called - names - state_vars - ContractAstValidator::BASIC_METHODS.to_a - StateVariableDefinitions.instance_methods
      
      net.flatten.tally.sort_by(&:second).reverse.to_h
      # nil
    end
    
    def a
      file = Rails.root.join('app', 'models', 'contracts', 'PublicMintERC20.rubidity').to_s
            
      ast = Unparser.parse(IO.read(file))
    end
    
    def b
      file = Rails.root.join('app', 'models', 'contracts', 'ERC20Locker.rubidity').to_s
            
      ast = Unparser.parse(IO.read(file))
      
      validator = new(ast)
      validator.validate_allowed_nodes
      validator.validate_top_level_structure
      validator.validate_contracts
      validator
    end
  end
  
  ALLOWED_NODE_TYPES = [:send, :sym, :pair, :lvar, :str, :begin, :int, :kwargs, :args, :block, :hash, :lvasgn, :index, :indexasgn, :array, :return, :if, :const, :nil, :true, :arg, :masgn, :mlhs, :op_asgn, :and, :procarg0, :lambda, :or, :dstr, :false].to_set.freeze
  
  BASIC_METHODS = [:+, :*, :-, :<, :>, :/, :%, :>=, :<=, :!, :**, :!=, :==, :<<, :>>, :[], :[]=, :<=>, :&, :|, :^, :~].to_set.freeze
  
  attr_accessor :ast
  
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end
  
  def initialize(ast = nil)
    self.ast = ast
  end
  
  def validate_allowed_nodes
    process(ast)
  end
  
  def validate_top_level_structure
    unless ast.type == :begin
      raise "Invalid top-level structure detected in #{ast}"
    end
    
    ast.children.each do |node|
      unless valid_top_level_block?(node)
        raise "Invalid top-level structure detected in #{node}"
      end
    end
    
    true
  # rescue
  #   ap ast
  #   raise
  end
  
  def contract_asts
    ast.children.select { |node| contract_definition?(node) }
  end
  
  def validate_contracts
    contract_asts.each do |contract_ast|
      unless valid_contract_ast?(contract_ast)
        raise "Invalid contract AST detected in #{contract_ast}"
      end
    end
  end
  # ContractAstValidator.b.contract_asts.first.children.last.children.count
  def function_defs
    ast = contract_asts.first
    contract_body = ast.children.last
    
    contract_body.children.select { |node| function_definition?(node) }
  end
  
  def valid_contract_ast?(node)
    return true if node.children.last.nil?
    
    begin_node = node.children.detect { |child| child.type == :begin }
    
    children = begin_node.present? ? begin_node.children : [node.children.last]
    
    children.all? do |child|
      answer = state_variable_definition?(child) ||
      event_definition?(child) ||
      struct_definition?(child) ||
      function_definition?(child)
      
      binding.pry unless answer
      answer
    end
  # rescue Exception => e
  #   ap node
  #   raise
  #   # binding.pry
  end

  def valid_top_level_block?(node)
    pragma_definition?(node) ||
    import_statement?(node) ||
    contract_definition?(node)
  end
  
  def state_variable_definition?(node)
    return unless node.type == :send
    
    receiver, method_name, *args = destructure_send_node(node)
    
    type_okay = StateVariableDefinitions.instance_methods.include?(method_name) ||
    structs.include?(method_name)
    
    (receiver.nil? &&
    type_okay &&
    args.size >= 1).tap do |result|
      if result
        var_name = if method_name == :array
          node.children[4].children.last
        else
          node.children.last.children.last
        end
        
        self.state_variables << var_name
      end
    end
  # rescue
  #   ap node
  #   raise
  #   # binding.pry
  #   # true
  end
  
  def event_definition?(node)
    return unless node.type == :send
    
    receiver, method_name, *args = destructure_send_node(node)
    
    receiver.nil? && method_name == :event &&
    args.map(&:type) == [:sym, :hash]
  end
  
  attr_accessor :structs
  
  def structs
    @structs ||= []
  end
  
  def struct_definition?(node)
    block_method?(node, method_name: :struct) do |send_node, args_node, body_node|
      # Validate that the send_node directly calls the 'struct' method with a symbol for the struct's name
      struct_name = send_node.children[2]
      valid_name = struct_name.type == :sym  # Ensure the struct's name is a symbol
  
      # Validate the body contains only valid property definitions
      valid_properties = body_node.type == :begin &&
                         body_node.children.all? { |child| state_variable_definition?(child) }
  
      (valid_name && valid_properties).tap do |result|
        self.structs << struct_name.children.first if result
      end
    end
  # rescue Exception => e
  #   ap node
  #   raise
  #   # binding.pry
    
  end
  
  def destructure_send_node(node)
    unless node.type == :send
      raise InvalidSendNode, "Node is not a send node: #{node}"
    end
    
    receiver, method_name, *args = *node
    
    [receiver, method_name, *args]
  end
  
  def contract_definition?(node)
    block_method?(
      node,
      method_name: :contract,
      receiver: nil
    ) do |send_node, args_node, body_node|
      receiver, method_name, *args = *send_node
      
      args_node.children.empty? &&
      args.length >= 1
    end
  end
  
  attr_accessor :function_names, :called_functions,
  :state_variables, :function_nodes
  
  def state_variables
    @state_variables ||= []
  end
  
  def function_names
    @function_names ||= []
  end
  
  def function_nodes
    @function_nodes ||= []
  end
  
  def called_functions
    @called_functions ||= []
  end
  
  def function_definition?(node)
    ap node
    # ap "KLSJDF"
    ap node.unparse
    raise unless FunctionDefinition.new(node).valid?
    return true
    
    if node.type == :send
      if node.children.first(2) == [nil, :constructor]
        self.function_names << :constructor
        function_nodes << node
        return true
      end
      
      if node.children.first(2) == [nil, :function]
        self.function_names << node.children[2].children.first
        
        return true
      end
    end
      
    block_method?(
      node,
      method_name: [:function, :constructor],
      receiver: nil
    ) do |send_node, args_node, body_node|
      receiver, method_name, *args = *send_node
      
      args_node.children.empty?.tap do |result|
        if method_name == :constructor
          if result
            self.function_names << :constructor
            function_nodes << node
          end
        else
          if result
            self.function_names << args.first.children.first.dup
            function_nodes << node
          end
        end
      end
    end
  # rescue Exception => e
  #   binding.pry
  end
  
  def self.block_method?(node, conditions = {})
    return false unless node.type == :block &&
      node.children.first(2).map(&:type) == [:send, :args]
  
    send_node, args_node, body_node = node.children
    receiver, method_name, *args = send_node.children
  
    basic_checks = conditions.all? do |key, value|
      case key
      when :method_name
        Array(value).include?(method_name)
      when :receiver
        receiver == value
      else
        true
      end
    end
    
    return unless basic_checks
  
    # Execute the block for further custom validation if provided
    block_given? ? yield(send_node, args_node, body_node) : true
  # rescue Exception => e
  #   ap e
  #   ap node
  #   binding.pry
  end
  delegate :block_method?, to: self
  
  def pragma_definition?(node)
    return unless node.type == :send
    
    receiver, method_name, *args = destructure_send_node(node)
      
    receiver.nil? && method_name == :pragma && args.size >= 1
  end
  
  def import_statement?(node)
    return unless node.type == :send
    
    receiver, method_name, *args = destructure_send_node(node)
      
    receiver.nil? &&
      method_name == :import &&
      args.size == 1 &&
      args.first.type == :str
  end
  
  def handler_missing(node)
    ensure_node_allowed!(node)
    
    if node.type == :send
      called_functions << node.children[1]
      
      if node.children[1] == :deployer
        # ap Unparser.unparse(node)
        # ap node
      end
    end
    
    node.children.each do |child|
      if child.is_a?(Parser::AST::Node)
        process(child)
      end
    end
    
    node
  end

  def ensure_node_allowed!(node)
    unless ALLOWED_NODE_TYPES.include?(node.type)
      ap node
      raise "Node type #{node.type} is not allowed."
    end
  end
end
