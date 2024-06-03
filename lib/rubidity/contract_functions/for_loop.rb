module ForLoop
  include ContractErrors
  
  def forLoop(args)
    start = args[:start]
    current_val = start || TypedVariable.create(:uint256, 0)
    
    condition = args[:condition]
    step = args[:step] || TypedVariable.create(:int256, 1)
    
    iteration_count = 0
    
    
    unless Kernel.instance_method(:block_given?).bind(self).call
      raise ArgumentError, 'Block is required'
    end
        
    while VM.unbox_and_get_bool(
      TransactionContext.log_call("ForLoop", "ForLoop", "condition") do
        condition.call(current_val)
      end
    )
      begin
        TransactionContext.log_call("ForLoop", "ForLoop", "yield") do
          TransactionContext.increment_gas("ForLoopIteration")
          yield(current_val)
        end
      ensure
        TransactionContext.log_call("ForLoop", self.class.name, "ForLoop step") do
          current_val += step
        
          iteration_count += 1
        end
      end
    end
  
    NullVariable.instance
  end
end
