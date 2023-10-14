class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :ethscription, :current_call,
  :transaction_hash, :transaction_index, :current_transaction, :contract_files
  
  def contract_files
    @contract_files ||= RubidityFile.registry
  end
  
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
  
  def main_contracts
    contract_files.values.flatten.select(&:is_main_contract)
  end
  
  def deployable_contracts
    main_contracts.reject(&:is_abstract_contract)
  end
  
  def types_that_implement(base_type)
    impl = main_contracts.detect{|i| i.name == base_type.to_s}
    deployable_contracts.select do |contract|
      contract.implements?(impl)
    end
  end
  
  def contract_from_version_and_type(
    implementation_version:,
    type:,
    include_abstract:
  )
    return unless implementation_version.present?
    
    contract_files[implementation_version].detect do |contract|
      contract.name == type.to_s && (include_abstract || !contract.is_abstract_contract)
    end
  end
  
  def type_valid_for_deploy?(implementation_version:, type:)
    contract_from_version_and_type(
      implementation_version: implementation_version,
      type: type,
      include_abstract: false
    ).present?
  end
  
  def guess_implementation_version_for(type:)
    implementation_version, _ = contract_files.find do |file_hash, contracts|
      contracts.any? { |c| c.name == type.to_s && c.is_main_contract }
    end
  
    if implementation_version.nil?
      matching_contracts = contract_files.select do |file_hash, contracts|
        contracts.any? { |c| c.name == type.to_s }
      end
  
      if matching_contracts.size == 1
        implementation_version, _ = matching_contracts.first
      end
    end
  
    implementation_version
  end
  
  def log_event(event)
    current_call.log_event(event)
  end
  
  def msg_sender
    TypedVariable.create_or_validate(:address, current_call.from_address)
  end
  
  def current_contract
    current_call&.to_contract
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
    Object.new.tap do |proxy|
      as_of = if Rails.env.test?
        "0xc59f53896133b7eee71167f6dbf470bad27e0af2443d06c2dfdef604a6ddf13c"
      else
        if ethscription.mock_for_simulate_transaction
          Ethscription.newest_first.second.ethscription_id
        else
          ethscription.ethscription_id
        end
      end
      
      proxy.define_singleton_method(:findEthscriptionById) do |id|
        id = TypedVariable.create_or_validate(:bytes32, id).value

        begin
          Ethscription.esc_findEthscriptionById(id, as_of)
        rescue ContractErrors::UnknownEthscriptionError => e
          raise ContractError.new(
            "findEthscriptionById: unknown ethscription: #{id}"
          )
        end
      end
      
      proxy.define_singleton_method(:currentTransactionHash) do
        TransactionContext.transaction_hash
      end
      
      proxy.define_singleton_method(:base64Encode) do |str|
        Base64.strict_encode64(str)
      end
    end
  end
end
