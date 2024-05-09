class BytesVariable < GenericVariable
  expose :length, :verifyTypedDataSignature
  
  def initialize(...)
    super(...)
  end
  
  def length
    val = value.sub(/^0x/, '')
    
    TypedVariable.create(:uint256, val.length / 2)
  end
  
  def verifyTypedDataSignature(
    type,
    message,
    verifyingContract:,
    domainName:,
    domainVersion:,
    signer:
  )
    unless type.is_a?(Hash) && type.keys.length == 1  
      raise ArgumentError.new("Invalid type")
    end

    # TODO: Input validation
    chainid = VM.deep_get_values(TransactionContext.block_chainid)
    
    typed_data = {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" }
        ]
      }.merge(type),
      primaryType: type.keys.first.to_s,
      domain: {
        name: domainName,
        version: domainVersion,
        chainId: chainid,
        verifyingContract: verifyingContract
      },
      message: message
    }
    
    signature = value
    
    TypedVariable.create(:bool, Eth::Signature.verify(typed_data, signature, signer, chainid))
  end
end
