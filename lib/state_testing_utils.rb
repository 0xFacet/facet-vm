module StateTestingUtils
  def self.compare_all(us_db_uri, them_db_uri, as_of_block)
    {
      contracts: compare_contracts_at_block(us_db_uri, them_db_uri, as_of_block),
      transaction_receipts: compare_transaction_receipts(us_db_uri, them_db_uri, as_of_block)
    }
  end

  def self.compare_contracts_at_block(us_db_uri, them_db_uri, as_of_block)
    ActiveRecord::Base.establish_connection(us_db_uri)
  
    our_contracts = Contract.all
    us = our_contracts.each_with_object({}) do |contract, hash|
      state = contract.states.where('block_number < ?', as_of_block).newest_first.first&.state
      hash[contract.address] = state if state
    end
  
    ActiveRecord::Base.establish_connection(them_db_uri)
    their_contracts = Contract.all
    them = their_contracts.each_with_object({}) do |contract, hash|
      state = contract.states.where('block_number < ?', as_of_block).newest_first.first&.state
      hash[contract.address] = state if state
    end
    
    unless our_contracts.map(&:address).sort == their_contracts.map(&:address).sort
      raise "Different contracts in the two databases!"
    end
  
    differing_states = us.each_with_object({}) do |(address, us_state), diff|
      them_state = them[address]
      if them_state && them_state != us_state
        diff[address] = deep_diff(us_state, them_state)
      end
    end
  
    differing_states
  ensure
    ActiveRecord::Base.establish_connection
  end
  
  def self.compare_transaction_receipts(us_db_uri, them_db_uri, as_of_block)
    ActiveRecord::Base.establish_connection(us_db_uri)
  
    us = TransactionReceipt.where('block_number < ?', as_of_block).newest_first.pluck(:transaction_hash, :status, :logs).map{|transaction_hash, status, logs| [transaction_hash, {status: status, logs: logs}]}.to_h
  
    ActiveRecord::Base.establish_connection(them_db_uri)
  
    them = TransactionReceipt.where('block_number < ?', as_of_block).newest_first.pluck(:transaction_hash, :status, :logs).map{|transaction_hash, status, logs| [transaction_hash, {status: status, logs: logs}]}.to_h
  
    differing_receipts = us.each_with_object({}) do |(transaction_hash, us_data), diff|
      them_data = them[transaction_hash]
      if them_data && (them_data[:status] != us_data[:status] || them_data[:logs] != us_data[:logs])
        diff[transaction_hash] = { local: us_data, remote: them_data }
      end
    end
  
    differing_receipts
  ensure
    ActiveRecord::Base.establish_connection
  end
  
  def self.deep_diff(us_state, them_state)
    diff = {}
  
    all_keys = us_state.keys | them_state.keys
  
    all_keys.each do |key|
      us_value = us_state[key]
      them_value = them_state[key]
  
      if us_value.is_a?(Hash) && them_value.is_a?(Hash)
        key_diff = deep_diff(us_value, them_value)
        diff[key] = key_diff unless key_diff.empty?
      elsif us_value.is_a?(Array) && them_value.is_a?(Array)
        if us_value.length != them_value.length
          diff[key] = { local: us_value, remote: them_value }
        else
          array_diff = us_value.zip(them_value).map.with_index { |(us_item, them_item), index| deep_diff(us_item, them_item) unless us_item == them_item }.compact
          diff[key] = array_diff unless array_diff.empty?
        end
      elsif us_value != them_value
        diff[key] = { local: us_value, remote: them_value }
      end
    end
  
    diff
  end
  
  def self.runtime_performance_stats(since = nil)
    since = since&.to_i || 24.hours.ago.to_i
  
    block_runtimes = TransactionReceipt.joins(:eth_block).where('eth_blocks.timestamp >= ?', since).group(:block_number).sum(:runtime_ms)
  
    block_runtimes_array = block_runtimes.values
  
    block_percentile_50 = block_runtimes_array.percentile(50).round
    block_percentile_95 = block_runtimes_array.percentile(95).round
    block_percentile_99 = block_runtimes_array.percentile(99).round
  
    percentiles = TransactionReceipt.where('block_timestamp >= ?', since).select("
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY runtime_ms) AS percentile_50,
      PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY runtime_ms) AS percentile_95,
      PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY runtime_ms) AS percentile_99
    ").take
  
    transaction_percentile_50 = percentiles.percentile_50
    transaction_percentile_95 = percentiles.percentile_95
    transaction_percentile_99 = percentiles.percentile_99
  
    {
      blocks: {
        percentile_50: block_percentile_50,
        percentile_95: block_percentile_95,
        percentile_99: block_percentile_99
      },
      transactions: {
        percentile_50: transaction_percentile_50,
        percentile_95: transaction_percentile_95,
        percentile_99: transaction_percentile_99
      }
    }
  end
end