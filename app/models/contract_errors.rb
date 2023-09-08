module ContractErrors
  class ContractError < StandardError
    attr_accessor :contract
    attr_accessor :error_status
  
    def initialize(message, contract)
      super(message)
      @contract = contract
    end
    
    def message
      return super if contract.blank?
      
      trace = !Rails.env.production? ? backtrace.join("\n") : ''
      
      "#{contract.class.name.demodulize} error: " + super + "#{trace} (contract id: #{contract.address})"
    end
  end
  
  class StaticCallError < StandardError; end  
  class TransactionError < StandardError; end
  class ContractRuntimeError < ContractError; end
  class ContractDefinitionError < ContractError; end
  class StateVariableTypeError < StandardError; end
  class VariableTypeError < StandardError; end
  class StateVariableMutabilityError < StandardError; end
  class ContractArgumentError < StandardError; end
  class CallingNonExistentContractError < TransactionError; end
  class UnknownEthscriptionError < StandardError; end
  class FatalNetworkError < StandardError; end
  class InvalidOverrideError < StandardError; end
  class FunctionAlreadyDefinedError < StandardError; end
end
