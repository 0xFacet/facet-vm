class TransactionReceipt < ApplicationRecord
  include FacetRailsCommon::OrderQuery
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, inverse_of: :transaction_receipts, optional: true, autosave: false

  belongs_to :contract, primary_key: 'address', foreign_key: 'effective_contract_address', optional: true, autosave: false
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :transaction_receipt, autosave: false
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash',
  optional: true, autosave: false, inverse_of: :transaction_receipt
  
  order_query :newest_first,
    [:block_number, :desc],
    [:transaction_index, :desc, unique: true]
  
  order_query :oldest_first,
    [:block_number, :asc],
    [:transaction_index, :asc, unique: true]
  
  def self.find_by_page_key(...)
    find_by_transaction_hash(...)
  end
  
  def stats
    TransactionStatsAnalyzer.new(self)
  end
  
  def self.a
    #  reload!; ContractBlockChangeLog.rollback_all_changes(19949273); $s.import_eth_blocks_until_done; EthBlock.a
    scope = TransactionReceipt.where(status: "success", function: 'callBuddyForUser').where.not(function: 'constructor')
    
    scope = TransactionReceipt.all
    
    AggregateTransactionStatsAnalyzer.new(
      # scope.last(5).first(1)
      scope.order("random()").limit(100_000)
    ).calculate_bucket_stats
  end
  
  # def aggregate_data()
  #   aggregated_data = {}
  #   receiver_data = Hash.new { |hash, key| hash[key] = { total_time: 0, call_count: 0 } }
  #   caller_data = Hash.new { |hash, key| hash[key] = { total_time: 0, call_count: 0 } }
  #   method_data = Hash.new { |hash, key| hash[key] = { total_time: 0, call_count: 0 } }
  
  #   function_stats.each do |key, runtimes|
  #     fn_caller, receiver, method_name = JSON.parse(key)
  #     total_time = runtimes.sum
  #     call_count = runtimes.size
  #     average_time = total_time / call_count
  
  #     aggregated_data[key] = {
  #       total_time: total_time,
  #       call_count: call_count,
  #       average_time: average_time
  #     }
  
  #     receiver_data[receiver][:total_time] += total_time
  #     receiver_data[receiver][:call_count] += call_count
  
  #     caller_data[fn_caller][:total_time] += total_time
  #     caller_data[fn_caller][:call_count] += call_count
  
  #     method_key = [receiver, method_name].to_json
  #     method_data[method_key][:total_time] += total_time
  #     method_data[method_key][:call_count] += call_count
  #   end
  
  #   { aggregated_data: aggregated_data, receiver_data: receiver_data, caller_data: caller_data, method_data: method_data }
  # end
  
  # def print_aggregated_data(aggregated_data)
  #   sorted_data = aggregated_data.sort_by { |_, data| -data[:average_time] }
  
  #   sorted_data.each do |key, data|
  #     puts "#{key}: #{data[:call_count]} calls, #{format('%.6f', data[:total_time])} seconds total, #{format('%.6f', data[:average_time])} seconds average"
  #   end
  # end
  
  # def print_receiver_data(receiver_data)
  #   sorted_data = receiver_data.sort_by { |_, data| -data[:total_time] }
  
  #   sorted_data.each do |receiver, data|
  #     average_time = data[:total_time] / data[:call_count]
  #     puts "#{receiver}: #{data[:call_count]} calls, #{format('%.6f', data[:total_time])} seconds total, #{format('%.6f', average_time)} seconds average"
  #   end
  # end
  
  # def print_caller_data(caller_data)
  #   sorted_data = caller_data.sort_by { |_, data| -data[:total_time] }
  
  #   sorted_data.each do |caller, data|
  #     average_time = data[:total_time] / data[:call_count]
  #     puts "#{caller}: #{data[:call_count]} calls, #{format('%.6f', data[:total_time])} seconds total, #{format('%.6f', average_time)} seconds average"
  #   end
  # end
  
  # def print_method_data(method_data)
  #   sorted_data = method_data.sort_by { |_, data| -data[:average_time] }
  
  #   sorted_data.each do |key, data|
  #     receiver, method_name = JSON.parse(key)
  #     average_time = data[:total_time] / data[:call_count]
  #     puts "#{receiver}##{method_name}: #{data[:call_count]} calls, #{format('%.6f', data[:total_time])} seconds total, #{format('%.6f', average_time)} seconds average time)} seconds average"
  #   end
  # end
  
  def page_key
    transaction_hash
  end
    
  def contract
    Contract.find_by_address(address)
  end
  
  def address
    effective_contract_address
  end
  
  def to
    to_contract_address
  end
  
  def from
    from_address
  end
  
  def contract_address
    created_contract_address
  end

  def to_or_contract_address
    to || contract_address
  end
  
  def as_json(options = {})
    methods = [
      :to,
      :from
    ]
    
    if ApiResponseContext.use_v1_api?
      methods += [:to_or_contract_address, :contract_address]
    else
      methods << :created_contract_address
    end
    
    super(
      options.merge(
        only: [
          :transaction_hash,
          :call_type,
          :runtime_ms,
          :block_timestamp,
          :status,
          :function,
          :args,
          :error,
          :logs,
          :block_blockhash,
          :block_number,
          :transaction_index,
          :gas_price,
          :gas_used,
          :transaction_fee,
          :return_value,
          :effective_contract_address
        ],
        methods: methods
      )
    ).with_indifferent_access
  end
  
  def failure?
    status.to_s == 'failure'
  end
  
  def success?
    status.to_s == 'success'
  end
  
  def self.pearson_correlation(x, y)
    n = x.size
    return 0 if n == 0
  
    sum_x = x.sum
    sum_y = y.sum
    sum_x_sq = x.map { |xi| xi**2 }.sum
    sum_y_sq = y.map { |yi| yi**2 }.sum
    sum_xy = x.zip(y).map { |xi, yi| xi * yi }.sum
  
    numerator = sum_xy - (sum_x * sum_y / n)
    denominator = Math.sqrt((sum_x_sq - (sum_x**2 / n)) * (sum_y_sq - (sum_y**2 / n)))
  
    return 0 if denominator == 0
  
    numerator / denominator
  end
  
  def self.gas_runtime_correlation_test
    sample = where.not(function: 'constructor').where(status: "success")#.
      # order("random()").limit(100_000)
    
      # sample = where(function: 'constructor').where(status: "success")
      
    data = sample.pluck(:runtime_ms, :facet_gas_used)
      
    runtimes = data.map { |d| d[0] }
    gas_used = data.map { |d| d[1] }
  
    pearson_correlation(runtimes, gas_used)
  end
end
