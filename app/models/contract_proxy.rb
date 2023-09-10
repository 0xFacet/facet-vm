class ContractProxy
  include ContractErrors
  
  attr_accessor :to_contract, :operation, :caller_address

  def initialize(to_contract:, operation:, caller_address:)
    @to_contract = to_contract
    @operation = operation
    @caller_address = caller_address
    
    define_contract_methods
  end
  
  def self.create(
    to_contract_address:,
    to_contract_type:,
    caller_address:,
    operation: :call
  )
    to_contract = Contract.find_by(address: to_contract_address)
  
    if to_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{to_contract_address}")
    end
    
    if to_contract_type && !to_contract.implements?(to_contract_type.to_s)
      raise ContractError.new("Contract doesn't implement interface: #{to_contract_address}, #{to_contract_type}", self)
    end
    
    new(
      to_contract: to_contract,
      operation: operation,
      caller_address: caller_address
    )
  end
  
  def method_missing(name, *args, &block)
    raise ContractError.new("Call to unknown function #{name}", to_contract)
  end

  private
  
  def define_contract_methods
    filtered_abi = to_contract.implementation.public_abi.select do |name, func|
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
        
        TransactionContext.set(msg_sender: caller_address) do
          to_contract.execute_function(
            name,
            user_args,
            persist_state: !func.read_only?
          )
        end
      end
    end
  end
end
