class TransactionContext < ActiveSupport::CurrentAttributes
  include ContractErrors
  
  attribute :call_stack, :log_event, :ethscription,
  :transaction_hash, :transaction_index, :current_transaction
  
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
  
  def call_stack
    self.call_stack = CallStack.new if super.nil?
    super
  end
  
  def msg_sender
    addr = call_stack.previous_frame&.to_contract_address || tx_origin
  end
  
  def current_contract
    call_stack.current_frame.to_contract
  end
  
  def this
    current_contract.implementation
  end
  
  def blockhash(input_block_number)
    unless input_block_number == block_number
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
        id = TypedVariable.create_or_validate(:ethscriptionId, id).value

        begin
          Ethscription.esc_findEthscriptionById(id, as_of)
        rescue ContractErrors::UnknownEthscriptionError => e
          raise ContractError.new(
            "findEthscriptionById: unknown ethscription: #{ethscription_id}"
          )
        end
      end
    end
  end
end
