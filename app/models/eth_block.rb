class EthBlock < ApplicationRecord
  has_many :ethscriptions, foreign_key: :block_number, primary_key: :block_number
  
  def self.process_contract_actions_until_done
    unprocessed_ethscriptions = Ethscription.where(contract_actions_processed_at: nil).count
    unimported_ethscriptions = Rails.cache.read("future_ethscriptions").to_i
    
    total_remaining = unprocessed_ethscriptions + unimported_ethscriptions
    
    Rails.cache.write("total_ethscriptions_behind", total_remaining)
    
    iterations = 0
    total_ethscriptions_processed = 0
    batch_ethscriptions_processed = 0
    
    start_time = Time.current
    batch_start_time = Time.current

    loop do
      iterations += 1

      just_processed = process_contract_actions_for_next_block_with_ethscriptions
      
      return unless just_processed
      
      batch_ethscriptions_processed += just_processed
      unprocessed_ethscriptions -= just_processed
      
      if iterations % 100 == 0
        curr_time = Time.current
        
        batch_elapsed_time = curr_time - batch_start_time
        
        ethscriptions_per_second = batch_ethscriptions_processed.zero? ? 0 : batch_ethscriptions_processed / batch_elapsed_time.to_f
        
        total_remaining -= batch_ethscriptions_processed
        
        puts "Processed #{iterations} blocks in #{batch_elapsed_time}s"
        puts " > Ethscriptions: #{batch_ethscriptions_processed}"
        puts " > Ethscriptions / s: #{ethscriptions_per_second}"
        puts " > Ethscriptions left: #{total_remaining}"
        
        Rails.cache.write("total_ethscriptions_behind", total_remaining)
        
        batch_start_time = curr_time
        batch_ethscriptions_processed = 0
      end
      
      break unless unprocessed_ethscriptions > 0
    end
  end
  
  def self.production_tester
    # heroku run rails runner "puts ContractTransaction.all.to_json" > ct.json
    
    j = JSON.parse(IO.read("ct.json"))
    
    max_block = j.map{|i| i['block_number']}.max
    
    them = j.map{|i| i['transaction_hash']}.to_set
    
    in_us_not_them = ContractTransaction.where("block_number >= ?", max_block).where.not(transaction_hash: them).to_set; nil
    in_them_not_us = them.to_set - ContractTransaction.pluck(:transaction_hash).to_set; nil
    
    in_us_not_them.length.zero? && in_them_not_us.length.zero?
  end
  
  def self.__pt2
    them = JSON.parse(IO.read("ctr.json")).sort_by{|i| [i['block_number'], i['transaction_index']]}
    max_block = them.map{|i| i['block_number']}.max
    
    us = ContractTransactionReceipt.includes(:contract_transaction).all.map(&:as_json).
      select{|i| i['block_number'] <= max_block}.sort_by{|i| [i['block_number'], i['transaction_index']]}; nil
    
    different_values = them.select do |theirs|
      ours = us.detect{|i| i['transaction_hash'] == theirs['transaction_hash']}
      ours != theirs
    end; nil
  end
  
  def self.__pt2
    them = JSON.parse(IO.read("ct.json")).index_by { |i| i['transaction_hash'] }
    max_block = them.values.map { |i| i['block_number'] }.max
  
    us = ContractTransactionReceipt.includes(:contract_transaction).all.map(&:as_json).
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
  
  def self.process_contract_actions_for_next_block_with_ethscriptions
    EthBlock.transaction do
      next_number = EthBlock.where(processing_state: 'pending').order(:block_number).limit(1).select(:block_number)

      locked_next_block = EthBlock.where(block_number: next_number)
                                  .lock("FOR UPDATE SKIP LOCKED")
                                  .first

      return unless locked_next_block
  
      ethscriptions = locked_next_block.ethscriptions.order(:transaction_index)
      # StackProf.run(mode: :wall, out: 'stackprof-cpu.dump', raw: true) do
      #   1000 / (Benchmark.ms{100.times{EthBlock.process_contract_actions_for_next_block_with_ethscriptions}} /  100.0)
      # end
      
      ethscriptions.each do |e|
        ContractTransaction.create_from_ethscription!(e)
      end
  
      locked_next_block.update_columns(
        processing_state: "complete",
        updated_at: Time.current
      )
  
      ethscriptions.length
    end
  end
  
  def build_new_ethscription(server_data)
    Ethscription.new(transform_server_response(server_data))
  end
  
  private
  
  def transform_server_response(server_data)
    {
      ethscription_id: server_data['transaction_hash'],
      block_number: block_number,
      block_blockhash: blockhash,
      transaction_index: server_data['transaction_index'],
      creator: server_data['creator'],
      current_owner: server_data['current_owner'],
      initial_owner: server_data['initial_owner'],
      creation_timestamp: timestamp,
      previous_owner: server_data['previous_owner'],
      content_uri: server_data['content_uri'],
      content_sha: Digest::SHA256.hexdigest(server_data['content_uri']),
      mimetype: server_data['mimetype']
    }
  end
end
