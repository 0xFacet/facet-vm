class Esc
  include ContractErrors

  def currentTransactionHash
    TransactionContext.transaction_hash
  end

  def base64Encode(str)
    Base64.strict_encode64(str)
  end
  
  def jsonEncode(obj)
    TypedVariable.create(:string, obj.to_json)
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
end
