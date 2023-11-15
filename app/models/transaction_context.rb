class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :current_call, :allow_list_contracts,
    :transaction_index, :current_transaction
  
  delegate :get_active_contract, to: :current_transaction
  
  STRUCT_DETAILS = {
    msg:    { attributes: { sender: :address } },
    tx:     { attributes: { origin: :address, current_transaction_hash: :bytes32 } },
    block:  { attributes: { number: :uint256, timestamp: :uint256, blockhash: :string } },
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
  
  def allow_listed_contract_class(init_code_hash, source_code = nil)
    unless allow_list_contracts.include?(init_code_hash)
      raise ContractError.new("Contract is not supported: #{init_code_hash.inspect}")
    end
    
    ContractArtifact.class_from_init_code_hash_or_source_code!(
      init_code_hash,
      source_code
    )
  end
  
  def log_event(event)
    current_call.log_event(event)
  end
  
  def msg_sender
    TypedVariable.create_or_validate(:address, current_call.from_address)
  end
  
  def current_contract
    current_call.to_contract
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
