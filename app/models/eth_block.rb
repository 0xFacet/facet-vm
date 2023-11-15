class EthBlock < ApplicationRecord
  extend StateTestingUtils
  has_many :ethscriptions, foreign_key: :block_number, primary_key: :block_number
  has_many :contract_transaction_receipts, foreign_key: :block_number, primary_key: :block_number
  
  scope :newest_first, -> { order(block_number: :desc) }
  scope :oldest_first, -> { order(block_number: :asc) }
  
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
      
      ethscriptions.each(&:process!)
  
      locked_next_block.update_columns(
        processing_state: "complete",
        updated_at: Time.current,
        transaction_count: locked_next_block.contract_transaction_receipts.count
      )
  
      ethscriptions.length
    end
  end
  
  def build_new_ethscription(server_data)
    Ethscription.new(transform_server_response(server_data))
  end

  def as_json(options = {})
    super(options.merge(
      only: [
        :block_number,
        :timestamp,
        :blockhash,
        :parent_blockhash,
        :imported_at,
        :processing_state,
        :transaction_count,
      ]
    )).tap do |json|
      if association(:contract_transaction_receipts).loaded?
        json[:contract_transaction_receipts] = contract_transaction_receipts.map(&:as_json)
      end
    end.with_indifferent_access
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
      mimetype: server_data['mimetype'],
      gas_price: server_data['gas_price'],
      gas_used: server_data['gas_price'],
      transaction_fee: server_data['gas_price'],
    }
  end
end
