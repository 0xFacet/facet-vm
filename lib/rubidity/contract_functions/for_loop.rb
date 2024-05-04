module ForLoop
  MAX_LOOPS = 100
  
  def forLoop(args)
    start_val = args[:start]&.value.to_i
    
    unless start_val >= 0
      raise ArgumentError, "Start value must be greater than or equal to 0"
    end
    
    start = TypedVariable.create(:uint256, start_val)
    current_val = start
    
    condition = args[:condition]
    step = args[:step] || TypedVariable.create(:int256, 1)
    max_iterations = args[:max_iterations]&.value || MAX_LOOPS
    
    iteration_count = 0
    
    if max_iterations > MAX_LOOPS
      raise ArgumentError, "Max iterations cannot exceed #{MAX_LOOPS}"
    end
    
    unless Kernel.instance_method(:block_given?).bind(self).call
      raise ArgumentError, 'Block is required'
    end
        
    while VM.unbox_and_get_bool(condition.call(current_val))
      begin
        yield(current_val)
      ensure
        current_val += step
        
        iteration_count += 1
        if iteration_count > max_iterations
          raise StandardError, "MaxIterationsExceeded"
        end
      end
    end
  
    NullVariable.instance
  end
end
