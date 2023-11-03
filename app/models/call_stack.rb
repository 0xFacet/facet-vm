class CallStack
  include ContractErrors
  
  MAX_CALL_COUNT = 100

  def initialize
    @frames = []
    @push_count = 0
  end

  def current_frame
    @frames.last
  end
  
  def execute_in_new_frame(
    to_contract_address: nil,
    to_contract_type: nil,
    to_contract_init_code_hash: nil,
    function: nil,
    args: {},
    type:,
    salt: nil
  )
    # We don't use to_contract_address because that is not
    # persisted until the tx is a success
    from_address = @push_count.zero? ?
      TransactionContext.tx_origin :
      TypedVariable.create_or_validate(:address, current_frame.to_contract.address)

    to_contract_address = TypedVariable.create_or_validate(:address, to_contract_address)
    
    call = TransactionContext.current_transaction.contract_calls.build(
      to_contract_address: to_contract_address.value,
      to_contract_type: to_contract_type,
      to_contract_init_code_hash: to_contract_init_code_hash,
      function: function,
      args: args,
      call_type: type,
      salt: salt,
      internal_transaction_index: @push_count,
      from_address: from_address.value
    )
    
    TransactionContext.set(current_call: call) do
      execute_in_frame(call)
    end
  end
  
  private
  
  def execute_in_frame(call)
    push(call)
    
    if @push_count > MAX_CALL_COUNT
      current_frame.assign_attributes(
        error: "Too many internal transactions",
        status: :failure
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
