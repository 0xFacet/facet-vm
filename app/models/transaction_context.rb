class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :ethscription, :current_call,
  :transaction_hash, :transaction_index, :current_transaction, :contract_files
  
  STRUCT_DETAILS = {
    msg:    { attributes: { sender: :address } },
    tx:     { attributes: { origin: :address } },
    block:  { attributes: { number: :uint256, timestamp: :datetime, blockhash: :string } },
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
  
  def contract_files=(new_files)
    return super(new_files) unless new_files
    
    names = new_files.values.map(&:name)
    
    if names.uniq != names
      raise "Duplicate contract names detected in contract_files"
    end
  
    super(new_files)
  end
  
  def implementation_from_init_code(init_code_hash)
    return unless contract_files.present?
    
    contract_files[init_code_hash]
  end
  
  def implementation_from_type(type)
    contract_files.values.detect do |contract|
      contract.name == type.to_s
    end
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
  
  def esc
    Esc.new(ethscription)
  end
end
