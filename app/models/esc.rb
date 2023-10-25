class Esc
  include ContractErrors

  def currentTransactionHash
    TransactionContext.transaction_hash
  end

  def base64Encode(str)
    Base64.strict_encode64(str)
  end
  
  def upgradeContract(new_init_code_hash)
    typed = TypedVariable.create_or_validate(:bytes32, new_init_code_hash)
    
    new_init_code_hash = typed.value.sub(/^0x/, '')
    
    target = TransactionContext.current_contract
    new_implementation_class = TransactionContext.implementation_from_init_code(new_init_code_hash)
    
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
