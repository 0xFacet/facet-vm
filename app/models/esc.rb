class Esc
  include ContractErrors

  def currentTransactionHash
    TypedVariable.create_or_validate(:bytes32, TransactionContext.transaction_hash)
  end

  def base64Encode(str)
    typed = TypedVariable.create_or_validate(:string, str)

    TypedVariable.create(:string, Base64.strict_encode64(typed.value))
  end
  
  def jsonEncode(**kwargs)
    TypedVariable.create(:string, kwargs.to_json)
  end
  
  def strIsAlphaNumeric(str)
    TypedVariable.create(:bool, !!(str =~ /\A[a-z0-9]+\z/i))
  end
  
  def getImplementationHash
    target = TransactionContext.current_contract.implementation_class
    
    code = "0x" + target.init_code_hash
    
    TypedVariable.create(:bytes32, code)
  end
  
  def upgradeContract(new_init_code_hash)
    typed = TypedVariable.create_or_validate(:bytes32, new_init_code_hash)
    
    new_init_code_hash = typed.value.sub(/^0x/, '')
    
    target = TransactionContext.current_contract
    new_implementation_class = TransactionContext.implementation_from_init_code(new_init_code_hash)
    
    unless target.implementation_class.is_upgradeable
      raise ContractError.new(
        "Contract is not upgradeable: #{target.implementation_class.name}",
        target
      )
    end
    
    unless new_implementation_class
      raise ContractError.new(
        "Implementation not found: #{new_init_code_hash}",
        target
      )
    end
    
    target.assign_attributes(
      current_type: new_implementation_class.name,
      current_init_code_hash: new_init_code_hash
    )
    
    nil
  end
  
  def verifyTypedDataSignature(
    type,
    message,
    verifyingContract:,
    domainName:,
    domainVersion:,
    signature:,
    signer:
  )
    unless type.is_a?(Hash) && type.keys.length == 1  
      raise ArgumentError.new("Invalid type")
    end
    
    message = message.transform_values do |value|
      value.respond_to?(:value) ? value.value : value
    end
    
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
        chainId: self.class.chain_id,
        verifyingContract: verifyingContract.respond_to?(:value) ? verifyingContract.value : verifyingContract
      },
      message: message
    }
    
    signer = signer.respond_to?(:value) ? signer.value : signer
    signature = signature.respond_to?(:value) ? signature.value : signature
    
    Eth::Signature.verify(typed_data, signature, signer, self.class.chain_id)
  end
  
  def self.chain_id
    if ENV.fetch("ETHEREUM_NETWORK") == "eth-mainnet"
      1
    elsif ENV.fetch("ETHEREUM_NETWORK") == "eth-goerli"
      5
    else
      raise "Unknown network: #{ENV.fetch("ETHEREUM_NETWORK")}"
    end
  end
end
