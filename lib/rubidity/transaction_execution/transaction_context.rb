class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :current_call, :transaction_index, :current_transaction, :active_contracts,
    :call_counts, :call_log_stack, :gas_counter, :contract_artifacts, :legacy_mode
  
  STRUCT_DETAILS = {
    msg:    { attributes: { sender: :address } },
    tx:     { attributes: { origin: :address, current_transaction_hash: :bytes32 } },
    block:  { attributes: { number: :uint256, timestamp: :uint256, blockhash: :bytes32, chainid: :uint256 } },
  }.freeze

  STRUCT_DETAILS.each do |struct_name, details|
    details[:attributes].each do |attr, type|
      full_attr_name = "#{struct_name}_#{attr}".to_sym

      attribute full_attr_name

      define_method("#{full_attr_name}=") do |new_value|
        new_value = TypedVariable.create_or_validate(type, new_value)
        super(new_value)
      end
    end
  end
  
  def transaction_hash
    tx.current_transaction_hash
  end
  
  def copy_artifacts_into_block
    contract_artifacts.values.each do |artifact|
      BlockContext.add_contract_artifact(artifact)
    end
  end
  
  def add_contract_artifact(artifact)
    artifact.transaction_hash = current_transaction.transaction_hash
    artifact.transaction_index = current_transaction.transaction_index
    
    contract_artifacts[artifact.init_code_hash] = artifact
  end
  
  def increment_gas(event_name)
    gas_counter.increment_gas(event_name)
  end
  
  def gas_limit
    ENV["GAS_LIMIT"].to_d
  end
  
  def log_call(call_type, receiver, method_name = nil)
    unless call_log_stack && call_counts
      return yield
    end
    
    unless method_name
      method_name = receiver
      receiver = call_type
    end
    
    key = [call_type, receiver, method_name]
  
    start_time = Time.now
    
    call_log_stack.push(key)
    
    composite_key = call_log_stack.to_json
    
    yield
  ensure
    if start_time
      runtime = (Time.now - start_time) * 1000.0
      call_counts[composite_key] ||= []
      call_counts[composite_key] << runtime
      
      call_log_stack.pop
    end
  end
  
  def get_existing_contract(address)
    already_active = self.active_contracts.detect do |contract|
      contract.deployed_successfully? &&
      contract.address == address
    end
    
    return already_active if already_active
    
    from_block = BlockContext.get_existing_contract(address)
    
    mark_active(from_block)
  end
  
  def mark_active(contract)
    if contract
      active_contracts << contract
      contract.state_manager.start_transaction
    end
    
    contract
  end
  
  def create_new_contract(
    address:,
    init_code_hash:
  )
    new_contract = BlockContext.create_new_contract(
      address: address,
      init_code_hash: init_code_hash,
    )
    
    mark_active(new_contract)

    new_contract.state_manager.set_implementation(
      init_code_hash: new_contract.current_init_code_hash,
      type: new_contract.current_type
    )
    
    new_contract
  end
  
  def log_event(event)
    current_index = BlockContext.get_and_increment_log_index
    
    current_call.log_event(event.merge(log_index: current_index))
  end
  
  def msg_sender
    TypedVariable.create_or_validate(:address, current_call.from_address)
  end
  
  def current_contract
    current_call.effective_contract
  end
  
  def current_address
    current_contract.address
  end
  
  def blockhash(input_block_number)
    input_block_number = VM.deep_get_values(input_block_number)
    
    unless input_block_number == block_number.value
      # TODO: implement
      raise "Not implemented"
    end
    
    block_blockhash
  end
end
