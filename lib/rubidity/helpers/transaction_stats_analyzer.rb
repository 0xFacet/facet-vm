class TransactionStatsAnalyzer
  attr_reader :nested_log, :function_aggregates

  def initialize(transaction_receipt)
    @transaction_receipt = transaction_receipt
    @function_stats = @transaction_receipt.function_stats.transform_keys do |key|
      JSON.parse(key)
    end
    @nested_log = build_nested_structure(@function_stats)
    @function_aggregates = calculate_aggregate_stats(@function_stats)
    add_missing_values(@nested_log)
    
    @nested_log.deep_transform_values!{|i| i.round(5)}
  end

  def all_leaf_nodes
    @function_stats.select do |key, _|
      node_is_leaf?(key)
    end
  end
  
  def node_is_leaf?(node)
    @function_stats.none? do |key, _|
      key & node == node && key.size > node.size
    end
  end
  
  def build_nested_structure(flat_log)
    nested_log = {}
    
    flat_log.each do |composite_key, runtimes|
      keys = composite_key
      current = nested_log
      # binding.irb if runtimes.all?(&:nil?)
      # binding.irb if runtimes.all?(&:nil?)
      
      runtimes = runtimes.map(&:to_f)
      
      keys.each_with_index do |key, index|
        if index == keys.size - 1
          current[key] ||= { sum: 0, count: 0, avg: 0, missing: 0, avg_missing: 0 }

          current[key][:sum] = runtimes.sum rescue binding.irb
          current[key][:count] = runtimes.size
          current[key][:avg] = runtimes.sum / runtimes.size.to_f
        else
          current[key] ||= { sum: 0, count: 0, avg: 0, missing: 0, avg_missing: 0 }
          current = current[key]
        end
      end
    end

    nested_log
  end
  
  def self.stat_key
    [:runtimes, :sum, :count, :avg, :missing, :avg_missing]
  end
  delegate :stat_key, to: :class
  
  def calculate_total_missing_time
    total_missing = 0
    total_sum = 0

    traverse_log(@nested_log) do |node|
      total_missing += node[:missing] if node[:missing]
      total_sum += node[:sum] if node[:sum]
    end

    percentage_missing = total_sum > 0 ? (total_missing / total_sum) * 100 : 0
    { total_missing: total_missing, percentage_missing: percentage_missing }
  end
  
  def traverse_log(node, &block)
    node.each do |key, value|
      next if stat_key.include?(key)

      if value.is_a?(Hash)
        block.call(value)
        traverse_log(value, &block)
      end
    end
  end
  
  def add_missing_values(node)
    node.each do |key, value|
      next if stat_key.include?(key)

      if value.is_a?(Hash)
        children_sum = value.reject { |k, _| stat_key.include?(k) }
                            .values.map { |v| v[:sum] }.sum
                            
        value[:missing] = value[:sum] - children_sum
        value.delete(:missing) if children_sum == 0
        
        if value[:missing]
          value[:avg_missing] = value[:missing] / value[:count].to_f
        else
          value.delete(:avg_missing)
        end
        
        add_missing_values(value)
      end
    end
  end

  def calculate_aggregate_stats(flat_log)
    aggregates = Hash.new { |hash, key| hash[key] = { total_time: 0, count: 0 } }

    flat_log.each do |composite_key, runtimes|
      runtimes = runtimes.map(&:to_f)
      
      keys = composite_key
      bottom_key = keys.last
      aggregates[bottom_key][:total_time] += runtimes.sum
      aggregates[bottom_key][:count] += runtimes.size
    end

    # Calculate average times
    aggregates.each do |key, data|
      data[:average_time] = data[:count] > 0 ? data[:total_time] / data[:count] : 0
    end

    aggregates
  end
end

class AggregateTransactionStatsAnalyzer
  attr_reader :aggregated_leaf_stats, :costs, :non_leaf_costs, :bucket_stats

  def initialize(transaction_receipts)
    @transaction_receipts = transaction_receipts
    @aggregated_leaf_stats = aggregate_leaf_node_stats
    @costs = calculate_leaf_costs
    @non_leaf_costs = calculate_non_leaf_costs
    @bucket_stats = calculate_bucket_stats
  end

  def aggregate_leaf_node_stats
    leaf_stats = {}

    results = Parallel.map(@transaction_receipts, in_processes: 8) do |receipt|
      analyzer = TransactionStatsAnalyzer.new(receipt)
      analyze_receipt(analyzer.nested_log)
    end

    results.each do |result|
      merge_leaf_stats(leaf_stats, result)
    end

    leaf_stats.each do |key, data|
      data[:average_time] = data[:count] > 0 ? data[:total_time] / data[:count] : 0
    end


    
    leaf_stats
  end
  
  def simplified_aggregated_leaf_stats
    operations = aggregated_leaf_stats
    
    operations.each do |key, stats|
      stats[:gas_cost] = stats[:average_time].round(2)
    end
    
    grouped_operations = operations.group_by { |_, stats| stats[:gas_cost] }

    # Output the grouped operations
    grouped_operations.each do |gas_cost, ops|
      puts "Gas Cost: #{gas_cost} ms"
      ops.each do |key, stats|
        puts "  Operation: #{key.join(' -> ')}"
      end
    end
    
  end

  def calculate_leaf_costs
    min_avg_time = @aggregated_leaf_stats.values.map { |v| v[:average_time] }.min

    costs = @aggregated_leaf_stats.transform_values do |stats|
      {
        total_time: stats[:total_time],
        count: stats[:count],
        average_time: stats[:average_time],
        # cost: (stats[:average_time] / min_avg_time * 1000).round
      }
    end

    costs
  end

  def calculate_non_leaf_costs
    non_leaf_costs = {}

    @transaction_receipts.each do |receipt|
      analyzer = TransactionStatsAnalyzer.new(receipt)
      analyze_non_leaf_nodes(analyzer.nested_log, non_leaf_costs)
    end

    min_overhead_cost = non_leaf_costs.values.map { |v| v[:overhead_cost] }.min

    non_leaf_costs.transform_values! do |stats|
      {
        total_time: stats[:total_time],
        count: stats[:count],
        average_time: stats[:average_time],
        overhead_cost: stats[:overhead_cost],
        missing: stats[:missing] || 0,
        avg_missing: stats[:avg_missing] || 0,
        # normalized_cost: (stats[:overhead_cost] / min_overhead_cost * 1000).round
      }
    end

    non_leaf_costs
  end

  def calculate_bucket_stats
    buckets = {
      "ContractFunction" => [],
      "ExternalContractCall" => [],
      "ForLoop_ForLoop_yield" => [],
      # "GlobalFunction_forLoop" => []
    }

    @non_leaf_costs.each do |key, stats|
      next if TransactionStatsAnalyzer.stat_key.include?(key)

      last_segment = key.last
      # ap stats
      # binding.irb if last_segment.first == "ContractFunction"
      
      if last_segment.first == "ContractFunction"
        buckets["ContractFunction"] << stats[:avg_missing] if stats[:avg_missing]
      elsif last_segment.first == "ExternalContractCall"
        buckets["ExternalContractCall"] << stats[:avg_missing] if stats[:avg_missing]
      elsif last_segment == ["ForLoop", "ForLoop", "yield"]
        # ap stats
        buckets["ForLoop_ForLoop_yield"] << stats[:avg_missing] if stats[:avg_missing]
      # elsif last_segment.first == "GlobalFunction" && last_segment.last == "forLoop"
        # buckets["GlobalFunction_forLoop"] << stats[:avg_missing] if stats[:avg_missing]
      end
      
      # if last_segment[0] == "ContractFunction" && last_segment[1] == "ContractFunction"
      #   buckets["ContractFunction"] << stats[:overhead_cost]
      # elsif last_segment[0] == "ExternalContractCall" && last_segment[1] == "ExternalContractCall"
      #   buckets["ExternalContractCall"] << stats[:overhead_cost]
      # elsif last_segment[0] == "GlobalFunction" && last_segment[1] == "GlobalFunction" && last_segment[2] == "forLoop"
      #   buckets["GlobalFunction_forLoop"] << stats[:overhead_cost]
      # end
    end
    
    bucket_stats = buckets.transform_values do |overheads|
      if overheads.empty?
        {
          average_overhead: nil,
          overhead_variance: nil,
          overhead_average_time_ms: nil,
          overhead_25th_percentile: nil,
          overhead_75th_percentile: nil,
          overhead_95th_percentile: nil
        }
      else
        {
          avg: overheads.mean,
          median: overheads.median,
          sd_deviation: overheads.standard_deviation,
          # overhead_variance: overheads.standard_deviation,
          # overhead_average_time_ms: overheads.mean,
          # overhead_25th_percentile: overheads.percentile(25),
          # overhead_75th_percentile: overheads.percentile(75),
          # overhead_95th_percentile: overheads.percentile(95)
        }
      end
    end

    bucket_stats.deep_transform_values{|i| i.round(5)}
    
    # buckets.transform_values do |values|
    #   values.descriptive_statistics
    # end.deep_transform_values{|i| i.round(5)}
    
  end

  private

  def analyze_receipt(nested_log)
    leaf_stats = {}
    collect_leaf_node_stats(nested_log, leaf_stats)

    plain_leaf_stats = leaf_stats.to_h { |k, v| [k, v.dup] }
    plain_leaf_stats.each do |key, value|
      value.default = nil
    end
    plain_leaf_stats
  end

  def collect_leaf_node_stats(node, leaf_stats, path = [])
    node.each do |key, value|
      next if [:runtimes, :sum, :count, :avg, :missing].include?(key)
      if value.is_a?(Hash)
        if value.keys.all? { |k| [:runtimes, :sum, :count, :avg, :missing].include?(k) }
          leaf_key = key
          leaf_stats[leaf_key] ||= { total_time: 0, count: 0 }
          leaf_stats[leaf_key][:total_time] += value[:sum]
          leaf_stats[leaf_key][:count] += value[:count]
        else
          collect_leaf_node_stats(value, leaf_stats, path + [key])
        end
      end
    end
  end

  def merge_leaf_stats(main_stats, new_stats)
    new_stats.each do |key, stats|
      main_stats[key] ||= { total_time: 0, count: 0 }
      main_stats[key][:total_time] += stats[:total_time]
      main_stats[key][:count] += stats[:count]
    end
  end

  def analyze_non_leaf_nodes(node, non_leaf_costs, path = [])
    node.each do |key, value|
      next if TransactionStatsAnalyzer.stat_key.include?(key)
      if value.is_a?(Hash)
        non_leaf_key = path + [key]
        if value.keys.any? { |k| !TransactionStatsAnalyzer.stat_key.include?(k) }
          non_leaf_costs[non_leaf_key] ||= { total_time: 0, count: 0, average_time: 0, overhead_cost: 0, missing: 0 }
          non_leaf_costs[non_leaf_key][:total_time] += value[:sum]
          non_leaf_costs[non_leaf_key][:count] += value[:count]
          non_leaf_costs[non_leaf_key][:average_time] = non_leaf_costs[non_leaf_key][:total_time] / non_leaf_costs[non_leaf_key][:count] if non_leaf_costs[non_leaf_key][:count] > 0
          non_leaf_costs[non_leaf_key][:overhead_cost] += value[:missing] if value[:missing]
          
          if value[:missing]
            non_leaf_costs[non_leaf_key][:missing] = value[:missing]
            non_leaf_costs[non_leaf_key][:avg_missing] = value[:avg_missing]
          end
          
          analyze_non_leaf_nodes(value, non_leaf_costs, non_leaf_key)
        else
          non_leaf_costs[non_leaf_key] ||= { total_time: 0, count: 0, average_time: 0, overhead_cost: 0 }
          non_leaf_costs[non_leaf_key][:total_time] += value[:sum]
          non_leaf_costs[non_leaf_key][:count] += value[:count]
          non_leaf_costs[non_leaf_key][:average_time] = non_leaf_costs[non_leaf_key][:total_time] / non_leaf_costs[non_leaf_key][:count] if non_leaf_costs[non_leaf_key][:count] > 0
        end
      end
    end
  end
end


# class AggregateTransactionStatsAnalyzer
#   attr_reader :aggregated_leaf_stats, :costs, :non_leaf_costs

#   def initialize(transaction_receipts)
#     @transaction_receipts = transaction_receipts
#     @aggregated_leaf_stats = aggregate_leaf_node_stats
#     @costs = calculate_leaf_costs
#     @non_leaf_costs = calculate_non_leaf_costs
#   end

#   def aggregate_leaf_node_stats
#     # Use a plain hash to avoid default proc issues
#     leaf_stats = {}

#     # Parallel processing using in_processes for CPU-bound tasks
#     results = Parallel.map(@transaction_receipts, in_processes: 16) do |receipt|
#       analyzer = TransactionStatsAnalyzer.new(receipt)
#       analyze_receipt(analyzer.nested_log)
#     end

#     # Merge the results from all processes
#     results.each do |result|
#       merge_leaf_stats(leaf_stats, result)
#     end

#     # Calculate average times
#     leaf_stats.each do |key, data|
#       data[:average_time] = data[:count] > 0 ? data[:total_time] / data[:count] : 0
#     end

#     leaf_stats
#   end

#   def calculate_leaf_costs
#     min_avg_time = @aggregated_leaf_stats.values.map { |v| v[:average_time] }.min

#     costs = @aggregated_leaf_stats.transform_values do |stats|
#       {
#         total_time: stats[:total_time],
#         count: stats[:count],
#         average_time: stats[:average_time],
#         cost: (stats[:average_time] / min_avg_time * 1000).round
#       }
#     end

#     costs
#   end

#   def calculate_non_leaf_costs
#     non_leaf_costs = {}

#     @transaction_receipts.each do |receipt|
#       analyzer = TransactionStatsAnalyzer.new(receipt)
#       analyze_non_leaf_nodes(analyzer.nested_log, non_leaf_costs)
#     end

#     # Calculate the overhead cost using the missing value
#     min_overhead_cost = non_leaf_costs.values.map { |v| v[:overhead_cost] }.min

#     non_leaf_costs.transform_values! do |stats|
#       {
#         total_time: stats[:total_time],
#         count: stats[:count],
#         average_time: stats[:average_time],
#         overhead_cost: stats[:overhead_cost],
#         normalized_cost: (stats[:overhead_cost] / min_overhead_cost * 1000).round
#       }
#     end

#     non_leaf_costs
#   end

#   private

#   def analyze_receipt(nested_log)
#     leaf_stats = {}
#     collect_leaf_node_stats(nested_log, leaf_stats)

#     # Convert to a plain hash without default proc for marshaling
#     plain_leaf_stats = leaf_stats.to_h { |k, v| [k, v.dup] }
#     plain_leaf_stats.each do |key, value|
#       value.default = nil
#     end
#     plain_leaf_stats
#   end

#   def collect_leaf_node_stats(node, leaf_stats, path = [])
#     node.each do |key, value|
#       next if [:runtimes, :sum, :count, :avg, :missing].include?(key)
#       if value.is_a?(Hash)
#         if value.keys.all? { |k| [:runtimes, :sum, :count, :avg, :missing].include?(k) }
#           leaf_key = key
#           leaf_stats[leaf_key] ||= { total_time: 0, count: 0 }
#           leaf_stats[leaf_key][:total_time] += value[:sum]
#           leaf_stats[leaf_key][:count] += value[:count]
#         else
#           collect_leaf_node_stats(value, leaf_stats, path + [key])
#         end
#       end
#     end
#   end

#   def merge_leaf_stats(main_stats, new_stats)
#     new_stats.each do |key, stats|
#       main_stats[key] ||= { total_time: 0, count: 0 }
#       main_stats[key][:total_time] += stats[:total_time]
#       main_stats[key][:count] += stats[:count]
#     end
#   end

#   def analyze_non_leaf_nodes(node, non_leaf_costs, path = [])
#     node.each do |key, value|
#       next if [:runtimes, :sum, :count, :avg, :missing].include?(key)
#       if value.is_a?(Hash)
#         if value.keys.any? { |k| ![:runtimes, :sum, :count, :avg, :missing].include?(k) }
#           non_leaf_key = path + [key]
#           non_leaf_costs[non_leaf_key] ||= { total_time: 0, count: 0, average_time: 0, overhead_cost: 0 }
#           non_leaf_costs[non_leaf_key][:total_time] += value[:sum]
#           non_leaf_costs[non_leaf_key][:count] += value[:count]
#           non_leaf_costs[non_leaf_key][:average_time] = non_leaf_costs[non_leaf_key][:total_time] / non_leaf_costs[non_leaf_key][:count] if non_leaf_costs[non_leaf_key][:count] > 0
#           non_leaf_costs[non_leaf_key][:overhead_cost] += value[:missing] if value[:missing]
#           analyze_non_leaf_nodes(value, non_leaf_costs, non_leaf_key)
#         end
#       end
#     end
#   end
# end

# class AggregateTransactionStatsAnalyzer
#   attr_reader :aggregated_leaf_stats, :costs

#   def initialize(transaction_receipts)
#     @transaction_receipts = transaction_receipts
#     @aggregated_leaf_stats = aggregate_leaf_node_stats
#     @costs = calculate_costs
#   end

#   def aggregate_leaf_node_stats
#     # Use a plain hash to avoid default proc issues
#     leaf_stats = Hash.new { |hash, key| hash[key] = { total_time: 0, count: 0 } }

#     # Parallel processing using in_processes for CPU-bound tasks
#     results = Parallel.map(@transaction_receipts, in_processes: 16) do |receipt|
#       analyzer = TransactionStatsAnalyzer.new(receipt)
#       analyze_receipt(analyzer.nested_log)
#     end

#     # Merge the results from all processes
#     results.each do |result|
#       merge_leaf_stats(leaf_stats, result)
#     end

#     # Calculate average times
#     leaf_stats.each do |key, data|
#       data[:average_time] = data[:count] > 0 ? data[:total_time] / data[:count] : 0
#     end

#     leaf_stats
#   end

#   def calculate_costs
#     min_avg_time = @aggregated_leaf_stats.values.map { |v| v[:average_time] }.min

#     costs = @aggregated_leaf_stats.transform_values do |stats|
#       {
#         total_time: stats[:total_time],
#         count: stats[:count],
#         average_time: stats[:average_time],
#         cost: (stats[:average_time] / min_avg_time * 1000).round
#       }
#     end

#     costs
#   end

#   private

#   def analyze_receipt(nested_log)
#     leaf_stats = Hash.new { |hash, key| hash[key] = { total_time: 0, count: 0 } }
#     collect_leaf_node_stats(nested_log, leaf_stats)

#     # Convert to a plain hash without default proc for marshaling
#     plain_leaf_stats = leaf_stats.to_h { |k, v| [k, v.dup] }
#     plain_leaf_stats.each do |key, value|
#       value.default = nil
#     end
#     plain_leaf_stats
#   end

#   def collect_leaf_node_stats(node, leaf_stats, path = [])
#     node.each do |key, value|
#       next if [:runtimes, :sum, :count, :avg, :missing].include?(key)
#       if value.is_a?(Hash)
#         if value.keys.all? { |k| [:runtimes, :sum, :count, :avg, :missing].include?(k) }
#           leaf_key = key
#           leaf_stats[leaf_key][:total_time] += value[:sum]
#           leaf_stats[leaf_key][:count] += value[:count]
#         else
#           collect_leaf_node_stats(value, leaf_stats, path + [key])
#         end
#       end
#     end
#   end

#   def merge_leaf_stats(main_stats, new_stats)
#     new_stats.each do |key, stats|
#       main_stats[key][:total_time] += stats[:total_time]
#       main_stats[key][:count] += stats[:count]
#     end
#   end
# end

# class AggregateTransactionStatsAnalyzer
#   attr_reader :aggregated_leaf_stats, :costs

#   def initialize(transaction_receipts)
#     @transaction_receipts = transaction_receipts
#     @aggregated_leaf_stats = aggregate_leaf_node_stats
#     @costs = calculate_costs
#   end

#   def aggregate_leaf_node_stats
#     leaf_stats = Hash.new { |hash, key| hash[key] = { total_time: 0, count: 0 } }

#     @transaction_receipts.each do |receipt|
#       analyzer = TransactionStatsAnalyzer.new(receipt)
#       collect_leaf_node_stats(analyzer.nested_log, leaf_stats)
#     end

#     # Calculate average times
#     leaf_stats.each do |key, data|
#       data[:average_time] = data[:count] > 0 ? data[:total_time] / data[:count] : 0
#     end

#     leaf_stats
#   end

#   def calculate_costs
#     min_avg_time = @aggregated_leaf_stats.values.map { |v| v[:average_time] }.min

#     costs = @aggregated_leaf_stats.transform_values do |stats|
#       (stats[:average_time] / min_avg_time * 100).round(-2)
#     end

#     costs.sort_by { |_, v| v }.reverse.to_h
#   end

#   private

#   def collect_leaf_node_stats(node, leaf_stats, path = [])
#     node.each do |key, value|
#       next if [:runtimes, :sum, :count, :avg, :missing].include?(key)

#       if value.is_a?(Hash)
#         if value.keys.all? { |k| [:runtimes, :sum, :count, :avg, :missing].include?(k) }
#           leaf_key = key
#           leaf_stats[leaf_key][:total_time] += value[:sum]
#           leaf_stats[leaf_key][:count] += value[:count]
#         else
#           collect_leaf_node_stats(value, leaf_stats, path + [key])
#         end
#       end
#     end
#   end
# end

