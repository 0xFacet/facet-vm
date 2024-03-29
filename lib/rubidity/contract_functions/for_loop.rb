module ForLoop
  MAX_LOOPS = 100
  
  def forLoop(start: 0, condition:, step: 1, max_iterations: MAX_LOOPS)
    if max_iterations > MAX_LOOPS
      raise ArgumentError, "Max iterations cannot exceed #{MAX_LOOPS}"
    end
    
    unless Kernel.instance_method(:block_given?).bind(self).call
      raise ArgumentError, 'Block is required'
    end
    
    current_val = start
    iteration_count = 0
  
    while condition.call(current_val)
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
  
    nil
  end
end
