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
    scope = TransactionReceipt.where(status: "success", function: 'callBuddyForUser').where.not(function: 'constructor')
    
    scope = TransactionReceipt.all
    
    AggregateTransactionStatsAnalyzer.new(
      # scope.last(5).first(1)
      scope.order("random()").limit(100_000)
    ).calculate_bucket_stats
  end
  
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
