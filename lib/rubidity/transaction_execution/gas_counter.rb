class GasCounter
  include ContractErrors
  
  attr_accessor :total_gas_used, :per_event_gas_used, :transaction_context
  
  delegate :gas_limit, to: :transaction_context
  
  EVENT_TO_COST = {
    "ExternalContractCall" => 0.5,
    "ContractFunction" => 0.5,
    "ForLoopIteration" => 0.3,
    "StorageMappingGet" => 0.03,
    "keccak256" => 0.03,
    "sqrt" => 0.03,
    "StorageMappingSet" => 0.05,
    "create2_address" => 0.1,
    "s" => 0.0005,
    "require" => 0.0005,
    "ContractFunctionArgGet" => 0.0005,
    "tx_current_transaction_hash" => 0.0005,
    "block_timestamp" => 0.0005,
    "ContractInitializer" => 0.0005,
    "StorageBaseSet" => 0.02,
    "ArrayIndexAssign" => 0.3,
    "TypedVariableVerifyTypedDataSignature" => 0.5,
    "StoragePointerStructGet" => 0.05,
    "StoragePointerStructSet" => 0.1,
    "StoragePointerArrayPush" => 0.25,
    "StoragePointerArrayPop" => 0.15,
    "upgradeImplementation" => 100,
  }.with_indifferent_access.freeze
  
  DEFAULT_GAS_COST = 0.01
  
  def initialize(transaction_context)
    @transaction_context = transaction_context
    @per_event_gas_used = {}
    @total_gas_used = 0
  end
  
  def enforce_gas_limit!
    if gas_limit > 0 && @total_gas_used > gas_limit
      raise ContractError, "Gas limit exceeded"
    end
    
    @total_gas_used
  end
  
  def increment_gas(event_name)
    cost = EVENT_TO_COST.fetch(event_name, DEFAULT_GAS_COST)
    
    @per_event_gas_used[event_name] ||= { gas_used: 0, count: 0 }
    @per_event_gas_used[event_name][:gas_used] += cost
    @per_event_gas_used[event_name][:count] += 1
    
    @total_gas_used += cost
    
    enforce_gas_limit!
  end
end

