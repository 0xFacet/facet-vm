class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :current_call, :transaction_index, :current_transaction, :current_event_index
  
  # delegate :get_active_contract, to: :current_transaction
  
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
  
  # def supported_contract_class(init_code_hash, source_code = nil, validate: true)
  #   validate_contract_support(init_code_hash) if validate
    
  #   find_and_build_class(init_code_hash) ||
  #     create_artifact_and_build_class(init_code_hash, source_code)
  # end
  
  def log_event(event)
    current_index = current_event_index
    self.current_event_index += 1
    
    current_call.log_event(event.merge(index: current_index))
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
  
  private
  
  # def validate_contract_support(init_code_hash)
  #   unless system_config.contract_supported?(init_code_hash)
  #     raise ContractError.new("Contract is not supported: #{init_code_hash.inspect}")
  #   end
  # end
  
  # def get_cached_class(init_code_hash)
  #   ContractArtifact.cached_class_as_of_tx_hash(
  #     init_code_hash,
  #     latest_artifact_hash
  #   )
  # end
  
  # def find_and_build_class(init_code_hash)
  #   unless current_transaction
  #     return get_cached_class(init_code_hash)
  #   end
    
  #   current = current_transaction.contract_artifacts.detect do |artifact|
  #     artifact.init_code_hash == init_code_hash
  #   end
  
  #   current&.build_class || get_cached_class(init_code_hash)
  # end
  
  # def create_artifact_and_build_class(init_code_hash, source_code = nil)
  #   raise "Need source code to create new artifact" unless source_code
  
  #   artifact = RubidityTranspiler.new(source_code).get_desired_artifact(init_code_hash)
    
  #   current_transaction.contract_artifacts.build(
  #     artifact.attributes.merge(
  #       block_number: block.number.value,
  #       transaction_index: transaction_index,
  #       internal_transaction_index: current_call.internal_transaction_index,
  #     )
  #   )
    
  #   artifact&.build_class
  # end
end
