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
    type:
  )
  
    call = TransactionContext.current_transaction.contract_calls.build(
      to_contract_address: to_contract_address,
      to_contract_type: to_contract_type,
      function: function,
      args: args,
      call_type: type,
      internal_transaction_index: @push_count,
      from_address: current_frame&.to_contract_address || TransactionContext.tx_origin,
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
