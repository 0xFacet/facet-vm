module AstSerializer
  MAX_SIZE = 2000.kilobytes
  MAX_DEPTH = 50

  def self.b
    ast = Unparser.parse(ContractArtifact.all.map(&:execution_source_code).join("\n\n"))
    # json_data = AstSerializer.serialize(ast, format: :json)
    cbor_data = AstSerializer.serialize(ast, format: :cbor)
    msgpack_data = AstSerializer.serialize(ast, format: :msgpack)
    
    Benchmark.bm do |x|
      # Uncomment to benchmark serialization as well
      # x.report("JSON serialize:") { 100.times { AstSerializer.serialize(ast, format: :json) } }
      # x.report("CBOR serialize:") { 100.times { AstSerializer.serialize(ast, format: :cbor) } }
      # x.report("MessagePack serialize:") { 100.times { AstSerializer.serialize(ast, format: :msgpack) } }
      # x.report("JSON deserialize:") { 100.times { AstSerializer.deserialize(json_data, format: :json) } }
      x.report("CBOR deserialize:") { 1000.times { AstSerializer.deserialize(cbor_data, format: :cbor) } }
      x.report("MessagePack deserialize:") { 1000.times { AstSerializer.deserialize(msgpack_data, format: :msgpack) } }
    end
  end
  
  def self.correct?
    ContractArtifact.all.map(&:execution_source_code).each do |code|
      ast = Unparser.parse(code)
      
      json_round_trip = AstSerializer.deserialize(AstSerializer.serialize(ast, format: :json), format: :json)
      cbor_round_trip = AstSerializer.deserialize(AstSerializer.serialize(ast, format: :cbor), format: :cbor)
      msgpack_round_trip = AstSerializer.deserialize(AstSerializer.serialize(ast, format: :msgpack), format: :msgpack)
      
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
    if data.bytesize > MAX_SIZE
      raise "Data too large"
    end
    
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

  class << self
    include Memery
  
    def node_to_hash(node)
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
    memoize :node_to_hash

    def hash_to_node(hash, depth = 0)
      if depth > MAX_DEPTH
        raise "Maximum depth reached"
      end
      
      type = hash['type'].to_sym
      children = hash['children'].map do |child|
        if child.is_a?(Hash)
          hash_to_node(child, depth + 1)
        elsif type != :str && child.is_a?(String)
          child.to_sym # Convert strings to symbols unless the parent type is :str
        else
          child # Leave as is if it's not a string or if parent type is :str
        end
      end
      Parser::AST::Node.new(type, children)
    end
    memoize :hash_to_node
  end
end
