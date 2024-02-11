class EthBlock < ApplicationRecord
  extend StateTestingUtils
  
  has_many :contract_states, foreign_key: :block_number, primary_key: :block_number
  has_many :ethscriptions, foreign_key: :block_number, primary_key: :block_number
  has_many :transaction_receipts, foreign_key: :block_number, primary_key: :block_number
  
  scope :newest_first, -> { order(block_number: :desc) }
  scope :oldest_first, -> { order(block_number: :asc) }
  
  scope :processed, -> { where.not(processing_state: "pending") }
  
  def self.most_recently_imported_blockhash
    max_block_number = max_processed_block_number
    EthBlock.where(block_number: max_block_number).pick(:blockhash)
  end
  
  def self.max_processed_block_number
    min_pending_block_number = EthBlock.where(processing_state: 'pending').minimum(:block_number)
    if min_pending_block_number
      EthBlock.processed.where('block_number < ?', min_pending_block_number).maximum(:block_number).to_i
    else
      EthBlock.processed.maximum(:block_number).to_i
    end
  end
  
  def self.process_contract_actions_until_done
    unprocessed_ethscriptions = Ethscription.unprocessed.count
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
      
      if iterations % 1 == 0
        curr_time = Time.current
        
        batch_elapsed_time = curr_time - batch_start_time
        
        ethscriptions_per_second = batch_ethscriptions_processed.zero? ? 0 : batch_ethscriptions_processed / batch_elapsed_time.to_f
        
        total_remaining -= batch_ethscriptions_processed
        
        Rails.cache.write("total_ethscriptions_behind", total_remaining)
        
        batch_start_time = curr_time
        batch_ethscriptions_processed = 0
      end
      
      break if iterations >= 100 || unprocessed_ethscriptions == 0
    end
  end
  
  def self.process_contract_actions_for_next_block_with_ethscriptions
    EthBlock.transaction do
      start_time = Time.current
      
      next_number = EthBlock.where(processing_state: 'pending').order(:block_number).limit(1).select(:block_number)

      locked_next_block = EthBlock.where(block_number: next_number)
                                  .lock("FOR UPDATE SKIP LOCKED")
                                  .first

      return unless locked_next_block
  
      ethscriptions = locked_next_block.ethscriptions.order(:transaction_index)
      
      BlockContext.set(
        system_config: SystemConfigVersion.current,
        current_block: locked_next_block,
        contracts: [],
        contract_artifacts: [],
        ethscriptions: ethscriptions,
      ) do
        BlockContext.process!
      end
      
      locked_next_block.update_columns(
        processing_state: "complete",
        updated_at: Time.current,
        transaction_count: ethscriptions.count{|e| e.processing_state == "success"},
        runtime_ms: (Time.current - start_time) * 1000
      )
  
      puts "Imported block #{locked_next_block.block_number} in #{locked_next_block.runtime_ms}ms"
      puts "> #{locked_next_block.transaction_count} ethscriptions"
      puts "> #{(locked_next_block.transaction_count / (locked_next_block.runtime_ms / 1000.0)).round(2)} ethscriptions / s"
      
      ethscriptions.length
    end
  end
  
  def build_new_ethscription(server_data)
    Ethscription.new(transform_server_response(server_data)).tap do |e|
      e.processing_state = "pending"
    end
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
      if association(:transaction_receipts).loaded?
        json[:transaction_receipts] = transaction_receipts.map(&:as_json)
      end
    end.with_indifferent_access
  end
  
  private
  
  def transform_server_response(server_data)
    {
      transaction_hash: server_data['transaction_hash'],
      block_number: block_number,
      block_blockhash: blockhash,
      transaction_index: server_data['transaction_index'],
      creator: server_data['creator'],
      initial_owner: server_data['initial_owner'],
      block_timestamp: timestamp,
      content_uri: server_data['content_uri'],
      mimetype: server_data['mimetype'],
      gas_price: server_data['gas_price'].to_i,
      gas_used: server_data['gas_used'].to_i,
      transaction_fee: server_data['transaction_fee'].to_i,
    }
  end
end
