class NodeChecker
  include AST::Processor::Mixin
  
  # Self removal is handled in the other class
  ALLOWED_NODE_TYPES = [:and, :arg, :args, :array, :begin, :block, :const, :dstr, :false, :hash, :if, :int, :lvar, :lvasgn, :masgn, :mlhs, :nil, :op_asgn, :or, :pair, :return, :send, :str, :sym, :true, :kwargs, :procarg0, :self, :lambda].to_set.freeze
  
  RESERVED_WORDS = [:__binding__, :__id__, :__send__, :equal?, :initialize, :instance_eval, :instance_exec, :method_missing, :singleton_method_added, :singleton_method_removed, :singleton_method_undefined, :BasicObject, :Object, :Kernel, :Module, :Class].to_set.freeze
  
  class InvalidCode < StandardError; end
  class NodeNotAllowed < StandardError; end
  
  def handler_missing(node)
    node.updated(nil, safe_process_all(node.children))
  end
  
  def process(node)
    unless ALLOWED_NODE_TYPES.include?(node.type)
      raise NodeNotAllowed, "Disallowed node type encountered: #{node.type}, #{node.inspect}"
    end
    
    validate_identifier(node)
    
    super(node)
  end
  
  def safe_process_all(nodes)
    nodes.to_a.map do |child|
      if child.is_a?(Parser::AST::Node)
        process(child)
      else
        child
      end
    end
  end
  
  def extract_identifier(node)
    identifier = case node.type
      # TODO: should :str have restrictions?
      when :lvasgn, :lvar, :arg, :sym
        node.children.first
      when :const, :send
        node.children[1]
      end
      
    return if identifier.nil?
      
    unless identifier.is_a?(Symbol)
      raise "Invalid identifier: #{identifier}"
    end
    
    identifier
  end

  def validate_identifier(node)
    value = extract_identifier(node)
    
    return unless value
    
    if value.length > 100
      raise NodeNotAllowed, "Identifier too long in #{node.type.inspect}"
    end
    
    unless value.to_s =~ /\A[a-z0-9_=\[\]<>+\-!*%\/?]+\z/i
      ap node
      raise NodeNotAllowed, "Identifier doesn't match /\\A[a-z0-9_=\[\]]+\\z/i: #{value.inspect}"
    end
    
    if RESERVED_WORDS.include?(value)
      raise NodeNotAllowed, "Use of reserved word #{value.inspect} in #{node.type.inspect}"
    end
    
    if value.starts_with?("__") && value.ends_with?("__")
      raise NodeNotAllowed, "Use of double underscore in #{node.type.inspect}"
    end
    
    if value.starts_with?("@") || value.starts_with?("::")
      raise NodeNotAllowed, "Use of instance variable or top-level constant in #{node.type.inspect} at line #{node.location.line}"
    end
  end
end
