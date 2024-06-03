class AstDeserializer < UltraBasicObject
  def initialize
  end
  
  def s(type, *children)
    # TODO: are these inputs safe
    ::Parser::AST::Node.new(type, children)
  end
  
  def self.execute(serialized_ast)
    context = new()
    
    # TODO: double underscore not safe in this context
    dummy_name = "__#{::SecureRandom.hex}__"
    
    singleton_class = (class << context; self; end)
    
    method_definition = "def #{dummy_name}; ::Kernel.binding; end"
      
    singleton_class.class_eval(method_definition)
    
    _binding = ::VM.send_method(context, dummy_name)
    
    ::Kernel.eval(serialized_ast, _binding)
  end
end

require 'json'
require 'cbor'
require 'msgpack'

# MessagePack::DefaultFactory.register_type(0x00, Symbol)

# class ASTSerializationBenchmark
#   def self.serialize_ast(node, format)
#     case format
#     when :msgpack
#       MessagePack.pack(node_to_hash(node))
#     when :cbor
#       CBOR.encode(node_to_hash(node))
#     else
#       raise "Unsupported format"
#     end
#   end

#   def self.deserialize_ast(data, format)
#     case format
#     when :msgpack
#       hash_to_node(MessagePack.unpack(data))
#     when :cbor
#       hash_to_node(CBOR.decode(data))
#     else
#       raise "Unsupported format"
#     end
#   end

#   def self.node_to_hash(node)
#     {
#       'type' => node.type.to_s,
#       'children' => node.children.map { |child|
#         if child.is_a?(Parser::AST::Node)
#           node_to_hash(child)
#         else
#           child
#         end
#       }
#     }
#   end

#   def self.hash_to_node(hash, depth = 0)
#     children = hash['children'].map { |child|
#       if child.is_a?(Hash)
#         hash_to_node(child, depth + 1)
#       else
#         child
#       end
#     }
#     Parser::AST::Node.new(hash['type'].to_sym, children)
#   # rescue => e
#   #   binding.irb
#   #   raise
#   end

#   def self.benchmark
#     ast = Unparser.parse(ContractArtifact.last.execution_source_code)

#     msgpack_data = serialize_ast(ast, :msgpack)
#     cbor_data = serialize_ast(ast, :cbor)

#     Benchmark.bm do |x|
#       x.report("CBOR serialize:") { 1000.times { serialize_ast(ast, :cbor) } }
#       x.report("MessagePack serialize:") { 1000.times { serialize_ast(ast, :msgpack) } }
#       x.report("CBOR deserialize:") { 1000.times { deserialize_ast(cbor_data, :cbor) } }
#       x.report("MessagePack deserialize:") { 1000.times { deserialize_ast(msgpack_data, :msgpack) } }
#     end
#   end
# end





module ASTSerializer3
  MAX_JSON_SIZE = 200.kilobytes

  def self.b
    ast = Unparser.parse(ContractArtifact.all.map(&:execution_source_code).join("\n\n"))
    json_data = ASTSerializer3.serialize(ast, format: :json)
    cbor_data = ASTSerializer3.serialize(ast, format: :cbor)
    msgpack_data = ASTSerializer3.serialize(ast, format: :msgpack)
    
    Benchmark.bm do |x|
      # Uncomment to benchmark serialization as well
      x.report("JSON serialize:") { 100.times { ASTSerializer3.serialize(ast, format: :json) } }
      x.report("CBOR serialize:") { 100.times { ASTSerializer3.serialize(ast, format: :cbor) } }
      x.report("MessagePack serialize:") { 100.times { ASTSerializer3.serialize(ast, format: :msgpack) } }
      x.report("JSON deserialize:") { 100.times { ASTSerializer3.deserialize(json_data, format: :json) } }
      x.report("CBOR deserialize:") { 100.times { ASTSerializer3.deserialize(cbor_data, format: :cbor) } }
      x.report("MessagePack deserialize:") { 100.times { ASTSerializer3.deserialize(msgpack_data, format: :msgpack) } }
    end
  end
  
  def self.correct?
    ContractArtifact.all.map(&:execution_source_code).each do |code|
      ast = Unparser.parse(code)
      
      json_round_trip = ASTSerializer3.deserialize(ASTSerializer3.serialize(ast, format: :json), format: :json)
      cbor_round_trip = ASTSerializer3.deserialize(ASTSerializer3.serialize(ast, format: :cbor), format: :cbor)
      msgpack_round_trip = ASTSerializer3.deserialize(ASTSerializer3.serialize(ast, format: :msgpack), format: :msgpack)
      
      unless json_round_trip == ast && cbor_round_trip == ast && msgpack_round_trip == ast
        puts "Failed round trip for #{code}"
        return false
      end
    end
    true
  end
  
  def self.serialize(node, format: :json)
    data = node_to_hash(node)
    case format
    when :json
      data.to_json
    when :cbor
      CBOR.encode(data)
    when :msgpack
      MessagePack.pack(data)
    else
      raise "Unsupported format"
    end
  end

  def self.deserialize(data, format: :json)
    case format
    when :json
      hash = JSON.parse(data)
    when :cbor
      hash = CBOR.decode(data)
    when :msgpack
      hash = MessagePack.unpack(data)
    else
      raise "Unsupported format"
    end
    hash_to_node(hash)
  end

  private

  def self.node_to_hash(node)
    {
      type: node.type.to_s,
      children: node.children.map do |child|
        if child.is_a?(Parser::AST::Node)
          node_to_hash(child)
        else
          child
        end
      end
    }
  end

  def self.hash_to_node(hash)
    type = hash['type'].to_sym
    children = hash['children'].map do |child|
      if child.is_a?(Hash)
        hash_to_node(child)
      elsif type != :str && child.is_a?(String)
        child.to_sym # Convert strings to symbols unless the parent type is :str
      else
        child # Leave as is if it's not a string or if parent type is :str
      end
    end
    Parser::AST::Node.new(type, children)
  end
end

module ASTSerializer
  MAX_JSON_SIZE = 200.kilobytes

  def self.b
    ast = Unparser.parse(ContractArtifact.all.map(&:execution_source_code).join("\n\n"))
    json_data = ASTSerializer.serialize(ast, format: :json)
    cbor_data = ASTSerializer.serialize(ast, format: :cbor)
    
    Benchmark.bm do |x|
      # x.report("JSON serialize:") { 1000.times { ASTSerializer.serialize(ast, format: :json) } }
      # x.report("CBOR serialize:") { 1000.times { ASTSerializer.serialize(ast, format: :cbor) } }
      x.report("JSON deserialize:") { 100.times { ASTSerializer.deserialize(json_data, format: :json) } }
      x.report("CBOR deserialize:") { 100.times { ASTSerializer.deserialize(cbor_data, format: :cbor) } }
    end
  end
  
  def self.serialize(node, format: :json)
    data = node_to_hash(node)
    case format
    when :json
      data.to_json
    when :cbor
      CBOR.encode(data)
    else
      raise "Unsupported format"
    end
  end

  def self.deserialize(data, format: :json)
    case format
    when :json
      # raise "Input size exceeds maximum allowed limit" if data.bytesize > MAX_JSON_SIZE
      hash = JSON.parse(data)
    when :cbor
      hash = CBOR.decode(data)
    else
      raise "Unsupported format"
    end
    hash_to_node(hash)
  end

  private

  def self.node_to_hash(node)
    {
      type: node.type.to_s,
      children: node.children.map { |child|
        if child.is_a?(Parser::AST::Node)
          node_to_hash(child)
        elsif child.is_a?(Symbol)
          { symbol: child.to_s }
        else
          child
        end
      }
    }
  end

  def self.hash_to_node(hash, depth = 0)
    children = hash['children'].map { |child|
      if child.is_a?(Hash) && child.key?('symbol')
        child['symbol'].to_sym
      elsif child.is_a?(Hash)
        hash_to_node(child, depth + 1)
      else
        child
      end
    }
    Parser::AST::Node.new(hash['type'].to_sym, children)
  end
end

module ASTSerializer2
  MAX_JSON_SIZE = 200.kilobytes

  def self.b
    ast = Unparser.parse(ContractArtifact.last.execution_source_code)
    json_data = ASTSerializer.serialize(ast, format: :json)
    cbor_data = ASTSerializer.serialize(ast, format: :cbor)
    
    Benchmark.bm do |x|
      # x.report("JSON serialize:") { 1000.times { ASTSerializer.serialize(ast, format: :json) } }
      # x.report("CBOR serialize:") { 1000.times { ASTSerializer.serialize(ast, format: :cbor) } }
      x.report("JSON deserialize:") { 1000.times { ASTSerializer.deserialize(json_data, format: :json) } }
      x.report("CBOR deserialize:") { 1000.times { ASTSerializer.deserialize(cbor_data, format: :cbor) } }
    end
  end
  
  def self.serialize(node, format: :cbor)
    data = node_to_hash(node)
    case format
    when :json
      data.to_json
    when :cbor
      CBOR.encode(data)
    else
      raise "Unsupported format"
    end
  end

  def self.deserialize(data, format: :cbor)
    case format
    when :json
      # raise "Input size exceeds maximum allowed limit" if data.bytesize > MAX_JSON_SIZE
      hash = JSON.parse(data)
    when :cbor
      hash = CBOR.decode(data)
    else
      raise "Unsupported format"
    end
    hash_to_node(hash)
  end

  private

  def self.node_to_hash(node)
    {
      type: node.type,
      children: node.children.map { |child|
        if child.is_a?(Parser::AST::Node)
          node_to_hash(child)
        else
          child
        end
      }
    }
  end

  def self.hash_to_node(hash, depth = 0)
    children = hash['children'].map { |child|
      if child.is_a?(Hash)
        hash_to_node(child, depth + 1)
      else
        child
      end
    }
    Parser::AST::Node.new(hash['type'], children)
  end
end

# module ASTSerializer
#   # Serializes a Parser::AST::Node to a JSON string
#   def self.serialize(node)
#     node_to_hash(node).to_json
#   end

#   # Deserializes a JSON string back to a Parser::AST::Node
  
#   MAX_JSON_SIZE = 200.kilobytes
  
#   def self.deserialize(json)
#     raise "Input size exceeds maximum allowed limit" if json.bytesize > MAX_JSON_SIZE

#     hash_to_node(JSON.parse(json))
#   end

#   private

#   # Converts a Parser::AST::Node to a hash
#   def self.node_to_hash(node)
#     {
#       type: node.type.to_s,  # Convert symbol to string
#       children: node.children.map { |child|
#         if child.is_a?(Parser::AST::Node)
#           node_to_hash(child)
#         elsif child.is_a?(Symbol)
#           { symbol: child.to_s }  # Mark symbols explicitly
#         else
#           child
#         end
#       }
#     }
#   end

#   # Converts a hash back to a Parser::AST::Node
#   def self.hash_to_node(hash, depth = 0)
#     # raise "AST is too deeply nested" if depth > MAX_DEPTH
    
#     children = hash['children'].map { |child|
#       if child.is_a?(Hash) && child.key?('symbol')
#         child['symbol'].to_sym  # Convert marked symbol back to symbol
#       elsif child.is_a?(Hash)
#         hash_to_node(child, depth + 1)
#       else
#         child
#       end
#     }
#     Parser::AST::Node.new(hash['type'].to_sym, children)
#   end
# end