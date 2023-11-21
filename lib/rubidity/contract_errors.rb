module ContractErrors
  class ContractError < StandardError
    attr_accessor :contract
    attr_accessor :error_status
  
    def initialize(message, contract = nil)
      super(message)
      @contract = contract
    end
    
    def message
      return super unless contract
      
      trace = !Rails.env.production? ? backtrace.join("\n") : ''
      klass = ::Object.instance_method(:class).bind(contract).call
      "#{klass.name} error: " + super
    end
  end
  
  class StaticCallError < StandardError; end  
  class TransactionError < StandardError; end
  class ContractDefinitionError < ContractError; end
  class VariableTypeError < StandardError; end
  class StateVariableMutabilityError < StandardError; end
  class ContractArgumentError < StandardError; end
  class CallingNonExistentContractError < TransactionError; end
  class InvalidOverrideError < StandardError; end
  class FunctionAlreadyDefinedError < StandardError; end
  class InvalidDestructuringError < StandardError; end
  class InvalidStateVariableChange < StandardError; end
  class UnknownInitCodeHash < StandardError; end
  class UnknownContractName < StandardError; end
  class InvalidEthscriptionError < StandardError; end
end
