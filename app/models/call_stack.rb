class CallStack
  include ContractErrors

  def initialize
    @frames = []
  end

  def push(frame)
    @frames.push(frame)
  end

  def pop
    @frames.pop
  end

  def current_frame
    @frames.last
  end
  
  def previous_frame
    @frames[-2]
  end

  def execute_in_new_frame(
    to_contract_address:,
    to_contract_type:,
    function_name:,
    function_args:,
    type:
  )
    frame = CallFrame.new(
      to_contract_address: to_contract_address,
      to_contract_type: to_contract_type,
      function_name: function_name,
      function_args: function_args,
      type: type
    )
    
    execute_in_frame(frame)
  end
  
  def execute_in_frame(frame)
    push(frame)
    
    begin
      return execute_current_frame
    ensure
      pop
    end
  end

  def execute_current_frame
    contract = current_frame.set_contract!
      
    contract.execute_function(
      current_frame.function_name.to_sym,
      current_frame.function_args,
      persist_state: current_frame.persist_state?
    )
  end
end
