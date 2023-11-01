module ForLoop
  def for_loop(start: 0, condition:, step: 1, max_iterations:)
    raise ArgumentError, 'Block is required' unless block_given?
    
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
