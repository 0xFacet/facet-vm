class AstPostProcessor
  extend Memoist
  class << self; extend Memoist; end
  
  class NodeNotAllowed < StandardError; end
  
  attr_accessor :ast
  
  ALLOWED_NODE_TYPES = [:and, :arg, :args, :array, :begin, :block, :const, :dstr, :false, :hash, :if, :int, :lvar, :lvasgn, :masgn, :mlhs, :nil, :op_asgn, :or, :pair, :return, :send, :str, :sym, :true].to_set.freeze
  
  def self.a
    paths = [
      Rails.root.join('app', 'models', 'contracts', '*.rubidity'),
      Rails.root.join('spec', 'fixtures', '*.rubidity'),
    ]

    files = paths.flat_map { |path| Dir.glob(path) }.reject{|path| path.to_s.include?("ERC20LiquidityPool.rubidity")}
    
    files.flat_map do |file|
      code = IO.read(file)
      instance = new(code)
      instance.process!
    end
  end
  
  def check_for_reserved_words!
    ast.each_node.each do |node|
      case node.type
      when :send
        check_reserved_word!(node.method_name, node)
      when :const
        check_reserved_word!(node.short_name, node)
        check_reserved_word!(node.namespace, node)
      when :lvasgn
        check_reserved_word!(node.name, node)
      when :lvar
        check_reserved_word!(node.children.first, node)
      when :arg
        check_reserved_word!(node.name, node)
      when :str, :sym
        check_reserved_word!(node.value, node)
      end
    end
  end
  
  def check_reserved_word!(value, node)
    return if value.nil?
    return if value.is_a?(Integer)
    
    value = value.to_sym
    
    if value.starts_with?("__") && value.ends_with?("__")
      raise NodeNotAllowed, "Use of double underscore in #{node.type.inspect} at line #{node.location.line}"
    end
    
    if value.starts_with?("@") || value.starts_with?("::")
      raise NodeNotAllowed, "Use of instance variable or top-level constant in #{node.type.inspect} at line #{node.location.line}"
    end
    
    if reserved_words.include?(value)
      raise NodeNotAllowed, "Use of reserved word #{value.inspect} in #{node.type.inspect} at line #{node.location.line}"
    end
  end
  # memoize :check_reserved_word!
  
  delegate :reserved_words, to: :class
  
  # TODO: Hard code list of reserved words
  def self.reserved_words
    reserved = [
      BasicObject,
      Object,
      Kernel,
      Module,
      Class
     ].map do |klass|
      [klass.name] +
      klass.public_instance_methods(true) + klass.public_methods(true) +
      klass.private_instance_methods(true) + klass.private_methods(true) +
      klass.protected_instance_methods(true) + klass.protected_methods(true)
    end.flatten.map(&:to_sym).to_set
    
    
    # reserved2 = [
    #   Object,
    #   Module
    #  ].map do |klass|
    #   klass.public_instance_methods(true) + klass.public_methods(true) +
    #   klass.private_instance_methods(true) + klass.private_methods(true) +
    #   klass.protected_instance_methods(true) + klass.protected_methods(true)
    # end.flatten.map(&:to_sym).to_set
    
    # reserved1 - reserved2 == Set.new
    
    # reserved = [
    #   BasicObject,
    #   Object,
    #   Kernel,
    #   Module,
    #   Class,
    #   Proc,
    #   Binding,
    #   Thread,
    #   ThreadGroup,
    #   Enumerator,
    #   Method,
    #   UnboundMethod,
    #   IO,
    #   File,
    #   Exception,
    #   ObjectSpace,
    #   GC,
    #   Mutex,
    #   Signal,
    #   Process
    #  ].map do |klass|
    #   [klass.name] +
    #   klass.public_instance_methods(false) + klass.public_methods(false) +
    #   klass.private_instance_methods(false) + klass.private_methods(false) +
    #   klass.protected_instance_methods(false) + klass.protected_methods(false)
    # end.flatten.map(&:to_sym).to_set
    
    # reserved += [:ENV, :exit, :abort, :system, :exec, :`, :$!, :$?, :$&, :$1, :$2, :$3, :$4, :$5, :$6, :$7, :$8, :$9, :$0, :$_, :respond_to_missing?, :respond_to?, :method_missing, ]
    
    allowed = [:<, :>, :>=, :<=, :!, :!=, :==, :name,
      :public, :private, :y, :include?,
      :require, :lambda, :new, :hash].to_set
  
  # :to_i,
  # :include?,
  # :times
    
    (reserved - allowed).freeze
  end
  class << self; memoize :reserved_words; end
  
  def initialize(string_or_ast)
    @ast = string_or_ast.is_a?(String) ?
      RuboCop::AST::ProcessedSource.new(string_or_ast, RUBY_VERSION.to_f).ast :
      string_or_ast
  end
  
  def process!
    ensure_nodes_allowed!
    # consts_to_sends
    check_for_reserved_words!
  end
  
  # def consts_to_sends
  #   matcher = -> (node) { node.type == :const }
    
  #   replacer = -> (node) {
  #     s(:send,
  #       s(:self), node.short_name)
  #   }
        
  #   @ast = modify_ast(ast, matcher, replacer)
  # end
  
  def ensure_nodes_allowed!
    ast.each_node do |node|
      unless ALLOWED_NODE_TYPES.include?(node.type)
        raise NodeNotAllowed, "Node type #{node} is not allowed."
      end
      
      if node.type == :const
        if node.namespace.present? || node.absolute?
          raise NodeNotAllowed, "Invalid constant reference: #{node.inspect}"
        end
      end
    end
  end
  
  # private
  
  # def s(type, *children)
  #   RuboCop::AST::SymbolNode.new(type, children)
  # end
  
  # def modify_ast(node, matcher, replacer)
  #   return unless node.is_a?(Parser::AST::Node)
  
  #   # Recursively modify child nodes first
  #   modified_children = node.children.map do |child|
  #     if child.is_a?(Parser::AST::Node)
  #       modify_ast(child, matcher, replacer) || child
  #     else
  #       child
  #     end
  #   end
  
  #   # Create a new node with potentially modified children
  #   new_node = node.updated(nil, modified_children)
  
  #   # Check if this node should be replaced
  #   matcher.call(new_node) ? replacer.call(new_node) : new_node
  # end
end
