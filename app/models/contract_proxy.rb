class ContractProxy
  include ContractErrors
  
  attr_accessor :contract, :operation

  def initialize(contract, operation:)
    @contract = contract
    @operation = operation
    define_contract_methods
  end
  
  def method_missing(name, *args, &block)
    raise ContractError.new("Call to unknown function #{name}", contract)
  end

  private
  
  def abi
    contract.abi
  end

  def define_contract_methods
    filtered_abi = contract.implementation.public_abi.select do |name, func|
      case operation
      when :static_call
        func.read_only?
      when :call
        !func.constructor?
      when :deploy
        true
      end
    end
    
    filtered_abi.each do |name, func|
      define_singleton_method(name) do |*args, **kwargs|
        user_args = { args: args, kwargs: kwargs }
        contract.execute_function(name, user_args, persist_state: !func.read_only?)
      end
    end
  end
end
