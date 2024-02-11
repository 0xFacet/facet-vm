module BenchmarkExtensions
  def msr(message = "Execution time")
    result = nil
    elapsed_time = Benchmark.ms { result = yield }
    puts "#{message}: #{elapsed_time.round} ms"
    result
  end
end

module Benchmark
  extend BenchmarkExtensions
end
