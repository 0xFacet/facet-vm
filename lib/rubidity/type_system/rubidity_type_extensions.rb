module RubidityTypeExtensions
  include ContractErrors
  
  module StringMethods
    include ContractErrors
    
    def base64Encode
      Base64.strict_encode64(value)
    end
    
    def base64Decode
      Base64.strict_decode64(value)
    end
    
    def isAlphaNumeric?
      TypedVariable.create(:bool, !!(value =~ /\A[a-z0-9]+\z/i))
    end
    
    def toPackedBytes
      TypedVariable.create(:bytes, "0x" + value.unpack1('H*'))
    end
  end

  module UintOrIntMethods
    include ContractErrors
    
    def toString
      value.to_s
    end
    
    def toPackedBytes
      bit_length = type.extract_integer_bits
      
      hex = (value % 2 ** bit_length).to_s(16)
      result = hex.rjust(bit_length / 4, '0')
      
      TypedVariable.create(:bytes, "0x" + result)
    end
  end
  
  module AddressMethods
    include ContractErrors
    
    def call(json_call_data = nil, **kwargs)
      calldata = kwargs.presence || JSON.parse(json_call_data.value)
      
      function, args = if calldata.is_a?(Hash)
        calldata = calldata.with_indifferent_access
        
        [calldata['function'], calldata['args']]
      elsif calldata.is_a?(Array)
        [calldata.first, calldata.drop(1)]
      end
      
      data = TransactionContext.call_stack.execute_in_new_frame(
        call_level: :low,
        to_contract_address: self,
        function: function,
        args: args,
        type: :call
      ).to_json
      
      DestructureOnly.new( 
        success: TypedVariable.create(:bool, true).to_proxy,
        data: TypedVariable.create(:string, data).to_proxy
      )
    rescue ContractError, TransactionError, JSON::ParserError => e
      return DestructureOnly.new(
        success: TypedVariable.create(:bool, false).to_proxy,
        data: TypedVariable.create(:string).to_proxy
      )
    end
  end
  
  module BytesMethods
    include ContractErrors
    
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
      message = VM.deep_get_values(message)
      type = VM.deep_get_values(type)
      domainName = VM.deep_get_values(domainName)
      domainVersion = VM.deep_get_values(domainVersion)
      signer = VM.deep_get_values(signer)
      verifyingContract = VM.deep_get_values(verifyingContract)
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
end
