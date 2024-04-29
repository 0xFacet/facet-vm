class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :current_call, :transaction_index, :current_transaction, :active_contracts
  
  STRUCT_DETAILS = {
    msg:    { attributes: { sender: :address } },
    tx:     { attributes: { origin: :address, current_transaction_hash: :bytes32 } },
    block:  { attributes: { number: :uint256, timestamp: :uint256, blockhash: :string, chainid: :uint256 } },
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

    define_method(struct_name) do
      struct_params = details[:attributes].keys
      struct_values = struct_params.map { |key| send("#{struct_name}_#{key}") }
    
      Struct.new(*struct_params).new(*struct_values)
    end
  end
  
  def transaction_hash
    tx.current_transaction_hash
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
    contract&.implementation&.state_proxy&.clear_changed
    active_contracts << contract if contract
    contract
  end
  
  def create_new_contract(...)
    from_block = BlockContext.create_new_contract(...)
    mark_active(from_block)
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
    unless input_block_number == block_number
      # TODO: implement
      raise "Not implemented"
    end
    
    block_blockhash
  end
end
