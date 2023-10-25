class Esc
  include ContractErrors
  
  def initialize(ethscription)
    @ethscription = ethscription
    @as_of = if Rails.env.test?
      "0xf5b2a0296d6be54483955e55c5f921f054e63c6ea6b3b5fc8f686d94f08b97e7"
    else
      if ethscription.mock_for_simulate_transaction
        Ethscription.newest_first.second.ethscription_id
      else
        ethscription.ethscription_id
      end
    end
  end

  def findEthscriptionById(id)
    id = TypedVariable.create_or_validate(:bytes32, id).value

    begin
      Ethscription.esc_findEthscriptionById(id, @as_of)
    rescue ContractErrors::UnknownEthscriptionError => e
      raise ContractError.new(
        "findEthscriptionById: unknown ethscription: #{id}"
      )
    end
  end

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
    
    new_state_vars = new_implementation_class.state_variable_definitions
    old_state_vars = target.implementation_class.state_variable_definitions
    
    unless new_state_vars == old_state_vars
      raise ContractError.new("Implementations have different storage layouts: old: #{old_state_vars.keys}, new: #{new_state_vars.keys}", target)
    end
    
    target.assign_attributes(
      current_type: new_implementation_class.name,
      current_init_code_hash: new_init_code_hash
    )
    
    nil
  end
end
