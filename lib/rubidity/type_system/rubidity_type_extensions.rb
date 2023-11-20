module RubidityTypeExtensions
  module StringMethods
    def base64Encode
      Base64.strict_encode64(value)
    end
    
    def escapeJSON
      value.to_json[1..-2]
    end
    
    def isAlphaNumeric?
      TypedVariable.create(:bool, !!(value =~ /\A[a-z0-9]+\z/i))
    end
  end

  module UintOrIntMethods
    def toString
      value.to_s
    end
  end
  
  module AddressMethods
    def call(json_call_data = '{}')
      calldata = JSON.parse(json_call_data)
  
      function = calldata['function']
      args = calldata['args']
      
      data = TransactionContext.call_stack.execute_in_new_frame(
        to_contract_address: self,
        function: function,
        args: args,
        type: :call
      ).to_json
      
      DestructureOnly.new( 
        success: true,
        data: TypedVariable.create(:string, data)
      )
    rescue ContractError, TransactionError, JSON::ParserError
      return DestructureOnly.new(
        success: false,
        data: TypedVariable.create(:string)
      )
    end
  end
  
  module BytesMethods
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
  
      message = message.transform_values do |value|
        value.respond_to?(:value) ? value.value : value
      end
  
      chainid = TransactionContext.block_chainid.value
      
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
          name: domainName.respond_to?(:value) ? domainName.value : domainName,
          version: domainVersion.respond_to?(:value) ? domainVersion.value : domainVersion,
          chainId: chainid,
          verifyingContract: verifyingContract.respond_to?(:value) ? verifyingContract.value : verifyingContract
        },
        message: message
      }
      
      signer = signer.respond_to?(:value) ? signer.value : signer
      signature = value
  
      Eth::Signature.verify(typed_data, signature, signer, chainid)
    end
  end
end
