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
      mimetypes: [ContractTransaction.required_mimetype],
      # initial_owner: "0x" + "0" * 40,
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
    EthBlock.transaction do
      db_blocks = EthBlock.order(block_number: :desc).limit(100)
  
      api_blocks = fetch_ethscriptions(db_blocks.last.block_number, max_blocks: 101)['blocks']
      
      db_block_hash_map = db_blocks.each_with_object({}) { |block, hash| hash[block.block_number] = block.blockhash }
      api_block_hash_map = api_blocks.each_with_object({}) { |block, hash| hash[block['block_number']] = block['blockhash'] }
      
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

      puts "Imported #{response['blocks'].length} blocks, #{response['blocks'].sum{|i| i['ethscriptions'].length}} ethscriptions. #{future_ethscriptions} future ethscriptions remain (#{Time.current - start_time}s))"
      
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
  
  def self.test_findEthscriptionById
    # All on goerli. Todo make into real test
    picture_ethscription = "0xe311b34c7ca0d37ed3c2139ed26696656de707fa39fb04f44f6a86d0f78cd69e"
    initial_owner = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97".downcase
    
    first_contract_interaction = "0x59311b2d3f0df7fa54671954b2d3f20ac9f012cf39fa45373033097f4285f074"
    
    transfer = "0xdeeb813391c34b43d5445ea97039488478cd7e20df7e15552c5eeb62492f31af"
    new_owner = "0x455E5AA18469bC6ccEF49594645666C587A3a71B".downcase
    
    second_contract_interaction = "0x95f24a00beb54b1c5b6cf902912b16d25b6d5ba6cf747ea3e7ccc0ba855505b6"
    
    _initial_owner = findEthscriptionById(picture_ethscription, as_of: first_contract_interaction)['current_owner']
    _new_owner = findEthscriptionById(picture_ethscription, as_of: second_contract_interaction)['current_owner']
    
    unless _initial_owner == initial_owner && _new_owner == new_owner
      raise "FAILURE"
    end
    "SUCCESS!"
  end
  
  def self.findEthscriptionById(ethscription_id, as_of:)
    maximum_attempts = 3 
    attempts = 0
    
    latest_block = if Rails.env.test?
      EthBlock.new(
        block_number: 9808217,
        blockhash: "0x915b5850f596a717b0634d722728e3ee7befde2d0b1ad89fdd55c6921c49ed06",
      )
    else
      EthBlock.order(block_number: :desc).where.not(imported_at: nil).first
    end
    
    begin
      response = query_api("ethscription_as_of",
        ethscription_id: ethscription_id,
        as_of_ethscription: as_of,
        latest_block_number: latest_block&.block_number,
        latest_block_hash: latest_block&.blockhash
      )
  
      case response.code
      when 200...300
        return transform_server_response(response.parsed_response['result'])
      when 404
        raise UnknownEthscriptionError.new("Unknown ethscription: #{ethscription_id}")
      else
        raise FatalNetworkError.new("Unexpected HTTP error: #{response.code}")
      end
  
    rescue FatalNetworkError => e
      attempts += 1
      if attempts < maximum_attempts
        sleep(1)
        retry
      else
        raise e
      end
    end
  end
  
  def self.transform_server_response(server_data)
    res = {
      ethscription_id: server_data['transaction_hash'],
      block_number: server_data['block_number'],
      block_blockhash: server_data['block_blockhash'],
      transaction_index: server_data['transaction_index'],
      creator: server_data['creator'],
      current_owner: server_data['current_owner'],
      initial_owner: server_data['initial_owner'] || server_data['current_owner'], # TODO
      creation_timestamp: server_data['creation_timestamp'],
      previous_owner: server_data['previous_owner'],
      content_uri: server_data['content_uri'],
      content_sha: Digest::SHA256.hexdigest(server_data['content_uri']),
      mimetype: server_data['mimetype']
    }.with_indifferent_access
  end
end
$s = EthscriptionSync #TODO: remove