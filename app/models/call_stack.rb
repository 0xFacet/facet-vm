class CallStack
  include ContractErrors

  def initialize
    @frames = []
    @push_count = 0
  end

  def push(frame)
    @frames.push(frame)
    
    @push_count += 1
  end

  def pop
    @frames.pop
  end

  def current_frame
    @frames.last
  end
  
  def execute_in_new_frame(
    to_contract_address: nil,
    to_contract_type: nil,
    function: nil,
    args: {},
    type:,
    salt: nil
  )
    # We don't use to_contract_address because that is not
    # persisted until the tx is a success
    from_address = @push_count.zero? ?
      TransactionContext.tx_origin :
      current_frame.to_contract.address
    
    call = TransactionContext.current_transaction.contract_calls.build(
      to_contract_address: to_contract_address,
      to_contract_type: to_contract_type,
      function: function,
      args: args,
      call_type: type,
      salt: salt,
      internal_transaction_index: @push_count,
      from_address: from_address
    )
    
    TransactionContext.set(current_call: call) do
      execute_in_frame(call)
    end
  end
  
  def execute_in_frame(call)
    push(call)
    
    begin
      return current_frame.execute!
    ensure
      pop
    end
  end
end
