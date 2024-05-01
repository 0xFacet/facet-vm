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
      
      calldata = if kwargs.empty?
        JSON.parse(json_call_data.value)
      else
        kwargs.transform_values{|i| i.unwrap.value}
      end
      
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
  
      message = message.deep_transform_values do |value|
        value = value.unwrap if value.respond_to?(:unwrap)
        value.respond_to?(:value) ? value.value : value
      end
      
      type = type.deep_transform_values do |value|
        value = value.unwrap if value.respond_to?(:unwrap)
        value.respond_to?(:value) ? value.value : value
      end
  
      chainid = TransactionContext.block_chainid.unwrap.value
      
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
          name: domainName.respond_to?(:unwrap) ? domainName.unwrap.value : domainName,
          version: domainVersion.respond_to?(:unwrap) ? domainVersion.unwrap.value : domainVersion,
          chainId: chainid,
          verifyingContract: verifyingContract.respond_to?(:unwrap) ? verifyingContract.unwrap.value : verifyingContract
        },
        message: message
      }
      
      signer = signer.respond_to?(:unwrap) ? signer.unwrap.value : signer
      signature = value
      
      TypedVariable.create(:bool, Eth::Signature.verify(typed_data, signature, signer, chainid))
    end
  end
end
