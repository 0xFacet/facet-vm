class EthscriptionSync
  include ContractErrors

  def self.query_api(url, query = {})
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/ethscriptions/" + url
    
    headers = {
      "Accept" => "application/json"
    }
    
    HTTParty.get(url, query: query, headers: headers)
  end
  
  def self.fetch_ethscriptions(
    new_block_number,
    max_ethscriptions: 2500,
    max_blocks: 10_000
  )
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/ethscriptions/newer_ethscriptions"
    
    our_count = Ethscription.where("block_number < ?", new_block_number).count
    
    query = {
      block_number: new_block_number,
      mimetypes: [
        ContractTransaction.transaction_mimetype,
        SystemConfigVersion.system_mimetype
      ],
      max_ethscriptions: max_ethscriptions,
      max_blocks: max_blocks,
      past_ethscriptions_count: our_count
    }
    
    headers = {
      "Accept" => "application/json"
    }
    
    response = HTTParty.get(url, query: query, headers: headers)
    
    response.parsed_response
  end

  def self.import_eth_blocks_until_done
    loop do
      future_ethscriptions = import_eth_block_batch
      
      Rails.cache.write("future_ethscriptions", future_ethscriptions)
      
      break if future_ethscriptions == 0
    end
  end
  
  def self.check_for_reorgs
    return unless EthBlock.exists?
    
    EthBlock.transaction do
      db_blocks = EthBlock.order(block_number: :desc).limit(100)

      url = ENV.fetch("INDEXER_API_BASE_URI") + "/blocks/newer_blocks"
    
      query = {
        block_number: db_blocks.last.block_number,
      }
      
      headers = {
        "Accept" => "application/json"
      }
      
      response = HTTParty.get(url, query: query, headers: headers)
      
      api_blocks = response.parsed_response

      db_block_hash_map = db_blocks.each_with_object({}) { |block, hash| hash[block.block_number] = block.blockhash }
      api_block_hash_map = api_blocks.each_with_object({}) { |block, hash| hash[block['block_number']] = block['block_hash'] }
      
      common_block_numbers = db_block_hash_map.keys & api_block_hash_map.keys

      reorged_blocks = common_block_numbers.select do |block_number|
        db_block_hash_map[block_number] != api_block_hash_map[block_number]
      end
      
      unless reorged_blocks.empty?
        EthBlock.where(block_number: reorged_blocks).each(&:destroy!)
        Rails.logger.warn "Deleted blocks due to reorg: #{reorged_blocks.join(', ')}"
      end
    end
  end
  
  def self.import_eth_block_batch
    EthBlock.transaction do
      start_time = Time.current
      
      previous_block = EthBlock.where(block_number: EthBlock.select("MAX(block_number)"))
                                  .limit(1)
                                  .lock("FOR UPDATE SKIP LOCKED")
                                  .first

      unless previous_block || !EthBlock.exists?
        return
      end
      
      next_block_number = (previous_block&.block_number || 0) + 1
      
      response = fetch_ethscriptions(next_block_number)
      
      if response.dig('error', 'resolution') == 'retry'
        return 0
      elsif response['error']
        raise "Unexpected error: #{response['error']}"
      end
      
      api_first_block = response['blocks'].first
      
      if previous_block && (previous_block.blockhash != api_first_block['parent_blockhash'])
        previous_block.destroy!
        Rails.logger.warn "Deleted block #{previous_block.block_number} because it had a different parent blockhash"
      else
        import_block_batch_without_reorg_check(response)
      end
      
      future_ethscriptions = Integer(response['total_future_ethscriptions'])

      puts "Imported #{response['blocks'].length} blocks, #{response['blocks'].sum{|i| i['ethscriptions'].length}} ethscriptions. #{future_ethscriptions} future ethscriptions remain (#{Time.current - start_time}s)"
      
      future_ethscriptions
    end
  end
  
  def self.import_block_batch_without_reorg_check(response)
    new_blocks = []
    new_ethscriptions = []

    response['blocks'].each do |block|
      state = block['ethscriptions'].empty? ? 'no_ethscriptions' : 'pending'

      new_block = EthBlock.new(
        block_number: block['block_number'],
        blockhash: block['blockhash'],
        parent_blockhash: block['parent_blockhash'],
        timestamp: block['timestamp'],
        imported_at: Time.current,
        processing_state: state
      )

      new_blocks << new_block

      block['ethscriptions'].each do |ethscription_data|
        new_ethscription = new_block.build_new_ethscription(ethscription_data)
        
        new_ethscriptions << new_ethscription
      end
    end

    EthBlock.import!(new_blocks)
    Ethscription.import!(new_ethscriptions)
  end
end

if Rails.env.development?
  $s = EthscriptionSync
end
