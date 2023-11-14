class Esc
  include ContractErrors

  def currentTransactionHash
    TransactionContext.transaction_hash
  end

  def base64Encode(str)
    Base64.strict_encode64(str)
  end
  
  def getImplementationHash
    target = TransactionContext.current_contract.implementation_class
    
    TypedVariable.create(:bytes32, target.init_code_hash)
  end
  
  def upgradeContract(new_init_code_hash, new_source_code)
    typed = TypedVariable.create_or_validate(:bytes32, new_init_code_hash)
    typed_source = TypedVariable.create_or_validate(:string, new_source_code)
    
    new_init_code_hash = typed.value
    
    target = TransactionContext.current_contract
    
    begin
      new_implementation_class = TransactionContext.allow_listed_contract_class(
        new_init_code_hash,
        typed_source.value.presence
      )
    rescue UnknownInitCodeHash => e
      raise ContractError.new(e.message, target)
    end
    
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
