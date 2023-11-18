class CallStack
  include ContractErrors
  
  MAX_CALL_COUNT = 100

  def initialize(transaction_context)
    @frames = []
    @push_count = 0
    @transaction_context = transaction_context
  end

  def current_frame
    @frames.last
  end
  
  def execute_in_new_frame(
    to_contract_address: nil,
    to_contract_init_code_hash: nil,
    to_contract_source_code: nil,
    function: nil,
    args: {},
    type:,
    salt: nil
  )
    # We don't use to_contract_address because that is not
    # persisted until the tx is a success
    from_address = @push_count.zero? ?
      @transaction_context.tx_origin :
      current_frame.to_contract.address
    
    from_address = TypedVariable.validated_value(:address, from_address)
    to_contract_init_code_hash = TypedVariable.validated_value(:bytes32, to_contract_init_code_hash)
    to_contract_address = TypedVariable.validated_value(:address, to_contract_address)
    
    current_transaction = @transaction_context.current_transaction
      
    call = @transaction_context.current_transaction.contract_calls.build(
      to_contract_address: to_contract_address,
      to_contract_init_code_hash: to_contract_init_code_hash,
      to_contract_source_code: to_contract_source_code,
      function: function,
      args: args,
      call_type: type,
      salt: salt,
      internal_transaction_index: @push_count,
      from_address: from_address,
      block_number: current_transaction.block_number,
      block_blockhash: current_transaction.block_blockhash,
      block_timestamp: current_transaction.block_timestamp,
      transaction_index: current_transaction.transaction_index,
      start_time: Time.current
    )
    
    @transaction_context.set(current_call: call) do
      execute_in_frame(call)
    end
  end
  
  private
  
  def execute_in_frame(call)
    push(call)
    
    if @push_count > MAX_CALL_COUNT
      current_frame.assign_attributes(
        error_message: "Too many internal transactions",
        status: :failure,
        end_time: Time.current
      )
      
      raise ContractError.new("Too many internal transactions")
    end
    
    current_frame.execute!
  ensure
    pop
  end
  
  def push(frame)
    @frames.push(frame)
    
    @push_count += 1
  end

  def pop
    @frames.pop
  end
end
