module ForLoop
  MAX_LOOPS = TypedVariable.create_as_proxy(:uint256, 100)
  
  def forLoop(start: 0, condition:, step: 1, max_iterations: MAX_LOOPS)
    if __facet_true__(max_iterations.gt(MAX_LOOPS))
      raise ArgumentError, "Max iterations cannot exceed #{MAX_LOOPS}"
    end
    
    unless Kernel.instance_method(:block_given?).bind(self).call
      raise ArgumentError, 'Block is required'
    end
    
    if start.is_a?(TypedVariableProxy)
      start = TypedVariableProxy.get_typed_variable(start).value
    end
    
    if step.is_a?(TypedVariableProxy)
      var = TypedVariableProxy.get_typed_variable(step)
      step, step_type = var.value, var.type
    end
    
    current_val = TypedVariable.create_as_proxy(:uint256, start)
    step = TypedVariable.create_as_proxy(step_type || :uint256, step)
    iteration_count = TypedVariable.create_as_proxy(:uint256, 0)
  
    while __facet_true__(condition.call(current_val))
      begin
        yield(current_val)
      ensure
        current_val += step
        iteration_count += TypedVariable.create_as_proxy(:uint256, 1)
        if __facet_true__(iteration_count.gt(max_iterations))
          raise StandardError, "MaxIterationsExceeded"
        end
      end
    end
  
    NullVariable.new
  end
end
