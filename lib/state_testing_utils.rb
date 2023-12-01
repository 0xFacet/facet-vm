module StateTestingUtils
  def production_tester
    # heroku run rails runner "puts ContractTransaction.all.to_json" > ct.json -a ethscriptions-vm-server 
    # heroku run rails runner "puts Contract.all.map{|i| {address: i.address, latest_state: i.current_state}}.to_json" > contracts.json -a ethscriptions-vm-server 
    
    j = JSON.parse(IO.read("ct.json"))
    
    max_block = j.map{|i| i['block_number']}.max
    
    them = j.map{|i| i['transaction_hash']}.to_set
    
    in_us_not_them = ContractTransaction.where("block_number >= ?", max_block).where.not(transaction_hash: them).to_set; nil
    in_them_not_us = them.to_set - ContractTransaction.pluck(:transaction_hash).to_set; nil
    
    in_us_not_them.length.zero? && in_them_not_us.length.zero?
  end
  
  def production_tester2
    # heroku run rails runner "puts TransactionReceipt.all.to_json" > ct.json -a ethscriptions-vm-server 
    # heroku run rails runner "puts Contract.all.map{|i| {address: i.address, latest_state: i.current_state}}.to_json" > contracts.json -a ethscriptions-vm-server 
  
    j = JSON.parse(IO.read("ct.json"))
  
    max_block = j.map{|i| i['block_number']}.max
  
    them = j.map{|i| [i['transaction_hash'], i['logs']]}.to_h
  
    us = TransactionReceipt.pluck(:transaction_hash, :logs).to_h
  
    differing_statuses = us.select { |hash, logs| them[hash] && them[hash] != logs }
  
    differing_statuses
  end
  
  def state_test
    cmd = %{heroku run rails runner "puts Contract.all.map{|i| {address: i.address, latest_state: i.current_state}}.to_json" -a #{ENV.fetch('HEROKU_APP_NAME')}}
    
    j = JSON.parse(`#{cmd}`)
    
    # j = JSON.parse(IO.read("contracts.json"));nil
    
    them = j.map{|i| [i['address'], i['current_state']]}.to_h
  
    us = Contract.pluck(:address, :current_state).to_h
    
    differing_states = us.each_with_object({}) do |(address, state), diff|
      if them[address] && them[address] != state
        diff[address] = { local: state, remote: them[address] }
      end
    end
  
    differing_states
  end
  
  def state_test2(us_db_name, them_db_name)
    ActiveRecord::Base.establish_connection(
      adapter:  'postgresql',
      host:     'localhost',
      database: us_db_name,
      username: `whoami`.chomp,
      password: ''
    )
    us = ContractState.pluck(:contract_address, :transaction_hash, :state).map{|address, transaction_hash, state| [[address, transaction_hash], state]}.to_h
  
    ActiveRecord::Base.establish_connection(
      adapter:  'postgresql',
      host:     'localhost',
      database: them_db_name,
      username: `whoami`.chomp,
      password: ''
    )
    them = ContractState.pluck(:contract_address, :transaction_hash, :state).map{|address, transaction_hash, state| [[address, transaction_hash], state]}.to_h
  
    differing_states = us.each_with_object({}) do |((address, transaction_hash), state), diff|
      if them[[address, transaction_hash]] && them[[address, transaction_hash]] != state
        diff[[address, transaction_hash]] = { local: state, remote: them[[address, transaction_hash]] }
      end
    end
  
    differing_states
  end
  
  def __pt2
    them = JSON.parse(IO.read("ctr.json")).sort_by{|i| [i['block_number'], i['transaction_index']]}
    max_block = them.map{|i| i['block_number']}.max
    
    us = TransactionReceipt.includes(:contract_transaction).all.map(&:as_json).
      select{|i| i['block_number'] <= max_block}.sort_by{|i| [i['block_number'], i['transaction_index']]}; nil
    
    different_values = them.select do |theirs|
      ours = us.detect{|i| i['transaction_hash'] == theirs['transaction_hash']}
      ours != theirs
    end; nil
  end
  
  def __pt2
    them = JSON.parse(IO.read("ct.json")).index_by { |i| i['transaction_hash'] }
    max_block = them.values.map { |i| i['block_number'] }.max
  
    us = TransactionReceipt.includes(:contract_transaction).all.map(&:as_json).
      select{|i| i['block_number'] <= max_block}.sort_by{|i| [i['block_number'], i['transaction_index']]}.index_by { |i| i['transaction_hash'] }; nil
    
      different_values = {}

      them.each do |tx_hash, theirs|
        ours = us[tx_hash]
        if ours != theirs
          differences = {}
    
          ours.keys.each do |key|
            if ours[key] != theirs[key]
              differences[key] = { 'us' => ours[key], 'them' => theirs[key] }
            end
          end
    
          different_values[tx_hash] = { 'us' => ours, 'them' => theirs, 'differences' => differences }
        end
      end
    
      different_values.to_a.map{|i| i.last['differences']}
  end
  
  def runtime_performance_stats
    block_runtimes = TransactionReceipt.group(:block_number).sum(:runtime_ms)

    block_runtimes_array = block_runtimes.values
    
    percentile_50 = block_runtimes_array.percentile(50).round
    percentile_95 = block_runtimes_array.percentile(95).round
    percentile_99 = block_runtimes_array.percentile(99).round
    
    puts "BLOCKS"
    puts "50th percentile: #{percentile_50} ms"
    puts "95th percentile: #{percentile_95} ms"
    puts "99th percentile: #{percentile_99} ms"
    
    percentiles = TransactionReceipt.select("
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY runtime_ms) AS percentile_50,
      PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY runtime_ms) AS percentile_95,
      PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY runtime_ms) AS percentile_99
    ").take
    
    percentile_50 = percentiles.percentile_50
    percentile_95 = percentiles.percentile_95
    percentile_99 = percentiles.percentile_99
    
    puts "TRANSACTIONS"
    puts "50th percentile: #{percentile_50} ms"
    puts "95th percentile: #{percentile_95} ms"
    puts "99th percentile: #{percentile_99} ms"
  end
end