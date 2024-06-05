class CombinedProcessor
  class InvalidCode < StandardError; end
  class NodeNotAllowed < StandardError; end
  
  BOX_FUNCTION_NAME = :__box__.to_s.freeze
  GET_BOOL_FUNCTION_NAME = :__get_bool__.to_s.freeze
  SIMPLE_NODES = [:true, :false, :nil].to_set.freeze
  LITERAL_NODES = [:int, :str, :sym, :lvar].to_set.freeze
  
  RESERVED_WORDS = [:__binding__, :__id__, :__send__, :equal?, :initialize, :instance_eval, :instance_exec, :method_missing, :singleton_method_added, :singleton_method_removed, :singleton_method_undefined, :BasicObject, :Object, :Kernel, :Module, :Class].map(&:to_s).to_set.freeze

  def initialize(serialized_ast)
    @ast_hash = JSON.parse(serialized_ast)
    @buffer = []
  end
  
  def self.b
    art = RubidityTranspiler.transpile_and_get("FacetSwapV1Pair")
    source = art.source_code
    
    v1 = ConstsToSends.process(source, box: false)
    serialized_ast = AstSerializer.serialize(Unparser.parse(v1), format: :json)
    
    num_iterations = 100  # Define the number of iterations

    Benchmark.bm do |x|
      x.report("consts_to_sends") do
        total_time = Benchmark.measure {
          num_iterations.times {
            ConstsToSends.process(source)
          }
        }.total
        puts "Average time per iteration (consts_to_sends): #{total_time / num_iterations} seconds"
      end
    
      x.report("combined_processor") do
        total_time = Benchmark.measure {
          num_iterations.times {
            processor = CombinedProcessor.new(serialized_ast)
            output = processor.process
          }
        }.total
        puts "Average time per iteration (combined_processor): #{total_time / num_iterations} seconds"
      end
    end
  end
  
  def process
    process_node(@ast_hash)
    @buffer.join
  end
  
  def self.example(code)
    serialized_ast = AstSerializer.serialize(Unparser.parse(code), format: :json)

    processor = CombinedProcessor.new(serialized_ast)
    output = processor.process
    is_match = ConstsToSends.process(code) == output
    
    [
      output,
      (is_match ? "Match" : ConstsToSends.process(code))
    ]
  end
  
  def box(code = nil, apply_boxing: true)
    if apply_boxing
      @buffer << "#{BOX_FUNCTION_NAME}("
    end
  
    begin
      if code
        @buffer << code
      else
        yield if block_given?
      end
    ensure
      @buffer << ")" if apply_boxing
    end
  end
  
  def process_node(node, inline_begin: true)
    return if node.nil?
    
    type = node['type'].to_sym
    children = node['children']
    
    validate_identifier(node)

    if SIMPLE_NODES.include?(type)
      box(type.to_s)
    elsif LITERAL_NODES.include?(type)
      literal = children.first
      
      box(literal_value(type, literal))
    else
      case type
      when :send
        process_send_node(children)
      when :lvasgn
        @buffer << "#{children.first} = "
        process_node(children[1])
      when :begin
        if children.length > 1
          children.each do |child|
            process_node(child)
            @buffer << "\n"
          end
        else
          @buffer << "("
          process_node(children.first)
          @buffer << ")"
          @buffer << "\n" unless inline_begin
        end
      when :if
        process_if_node(children)
      when :and, :or
        process_logical_operation(type, children)
      when :hash
        process_hash_node(children)
      when :kwargs
        process_kwargs_node(children)
      when :array
        process_array_node(children)
      when :pair
        process_pair_node(children)
      when :masgn
        process_masgn_node(children)
      when :return
        process_return_node(children)
      when :block
        process_block_node(children)
      else
        raise "Unsupported node type: #{type}"
      end
    end
  # rescue => e
  #   binding.irb
  end
  
  def process_return_node(children)
    @buffer << "return "
    @buffer << "("
    process_node(children.first || s(:nil))
    @buffer << ")"
  end
  
  def process_array_node(children)
    box do
      @buffer << "["
      children.each_with_index do |child, index|
        process_node(child)
        @buffer << ", " unless index == children.size - 1
      end
      @buffer << "]"
    end
  end
  
  def process_hash_node(children)
    box do
      @buffer << "{ "
      children.each_with_index do |child, index|
        process_node(child)
        @buffer << ", " unless index == children.size - 1
      end
      @buffer << " }"
    end
  end

  def process_kwargs_node(children)
    children.each_with_index do |child, index|
      process_node(child)
      @buffer << ", " unless index == children.size - 1
    end
  end
  
  def process_pair_node(children)
    key, value = *children
    
    unless key['type'] == 'sym'
      raise "Unsupported node type: #{key['type']}"
    end
    
    @buffer << key['children'].first
    @buffer << ": "
    
    process_node(value)
  end
  
  def literal_value(type, value)
    case type
    when :str then value.inspect
    when :sym then value.to_sym.inspect
    else value.to_s
    end
  end
  
  def process_send_node(children, box: true)
    box(apply_boxing: box) do
      receiver, method_name, *args = *children
      
      parentheses_needed = requires_parentheses?(receiver, method_name, args)

      if %w[+ - * / == != > < >= <=].include?(method_name)
        process_node(receiver)
        @buffer << " #{method_name} "
        process_node(args.first)
      else
        if receiver
          process_node(receiver)
          @buffer << "."
        end
  
        @buffer << "#{method_name}"
        @buffer << "(" if parentheses_needed
        args.each_with_index do |arg, index|
          process_node(arg, inline_begin: true)
          @buffer << ", " unless index == args.size - 1
        end
        @buffer << ")" if parentheses_needed
      end
    end
  end
  
  def requires_parentheses?(receiver, method_name, args)
    return true unless args.empty?
  
    method_name.to_s.match?(/^[A-Z]/) && receiver.nil?
  end

  def process_if_node(children)
    condition, if_true, if_false = *children
    @buffer << "if __get_bool__("
    process_node(condition)
    @buffer << ")\n  "
    process_node(if_true)
    
    if if_false
      @buffer << "\nelse\n  "
      process_node(if_false)
    end
    
    @buffer << "\nend"
  end

  def process_logical_operation(type, children)
    type_as_string = type == :and ? "&&" : "||"
    left, right = *children
  
    box do
      @buffer << "__get_bool__("
      process_node(left)
      @buffer << ")"
  
      @buffer << " #{type_as_string} "
  
      @buffer << "__get_bool__("
      process_node(right)
      @buffer << ")"
    end
  end
  
  # NOTE: the left hand side values will be unboxed
  def process_masgn_node(children)
    left, right = *children
        
    @buffer << left['children'].map do |child|
      unless child['type'] == 'lvasgn'
        raise "Unsupported node type: #{child['type']}"
      end
      
      child['children'].first
    end.join(", ")
    
    @buffer << " = "
    
    process_node(right)
  end
  
  def s(type, children = [])
    {
      "type" => type.to_s,
      "children" => children
    }
  end
  
  def process_block_node(children)
    send_node, args, body = *children
    
    body ||= s(:nil)
    
    if send_node['type'] == 'lambda'
      # Start the lambda expression
      @buffer << "->("
  
      # Check if there are any arguments
      if args['children'].empty?
        # No arguments, so nothing between the parentheses
        @buffer << ")"
      else
        # Process each argument and join them with commas
        @buffer << args['children'].map { |arg| extract_arg_name(arg) }.join(", ")
        @buffer << ")"
      end
  
      # Start the block
      @buffer << " {\n"
  
      # Process the body of the lambda
      process_node(body)
  
      # Close the lambda block
      @buffer << "\n}"
      return
    end
    
    box do
      process_send_node(send_node['children'], box: false)
      
      if args['children'].empty?
        @buffer << " {\n"
      else
        @buffer << " { |"
        args['children'].each_with_index do |arg, index|
          arg_name = extract_arg_name(arg)
          @buffer << arg_name
          @buffer << ", " unless index == args['children'].size - 1
        end
        @buffer << "| "
      end
    
      # Process the body of the block
      process_node(body)
    
      # Close the block
      @buffer << "\n}"
    end
  end
  
  def extract_arg_name(arg)
    if arg['type'].to_sym == :procarg0
      arg['children'].first['children'].first
    else
      arg['children'].first
    end
  end
  
  def extract_identifier(node)
    case node['type'].to_sym
    # TODO: should :str have restrictions?
    when :lvasgn, :lvar, :arg, :sym
      node['children'].first
    when :send
      node['children'][1]
    end
  end

  def validate_identifier(node)
    value = extract_identifier(node)
    
    return unless value
    
    if value.length > 100
      raise NodeNotAllowed, "Identifier too long in #{node['type'].inspect}"
    end
    
    unless value.to_s =~ /\A[a-z0-9_=\[\]<>+\-!*%\/?]+\z/i
      raise NodeNotAllowed, "Identifier doesn't match /\\A[a-z0-9_=\[\]]+\\z/i: #{value.inspect}"
    end
    
    if RESERVED_WORDS.include?(value)
      raise NodeNotAllowed, "Use of reserved word #{value.inspect} in #{node['type'].inspect}"
    end

    # TODO: "__ERC20_constructor__"
    # if value.starts_with?("__") && value.ends_with?("__")
    #   raise NodeNotAllowed, "Use of double underscore in #{node['type'].inspect}"
    # end
    
    if value.starts_with?("@") || value.starts_with?("::")
      raise NodeNotAllowed, "Use of instance variable or top-level constant in #{node['type'].inspect} at line #{node['location']['line']}"
    end
  end
end
