class EthscriptionSync
  include ContractErrors

  def self.query_api(url, query = {})
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/ethscriptions/" + url
    
    headers = {
      "Accept" => "application/json"
    }
    
    HTTParty.get(url, query: query, headers: headers)
  end
  
  def self.fetch_ethscriptions(new_block_number)
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/ethscriptions/newer_ethscriptions"
    
    query = {
      block_number: new_block_number,
      mimetypes: [ContractTransaction.required_mimetype],
      # initial_owner: "0x" + "0" * 40,
      max_ethscriptions: 1000,
      max_blocks: 10_000
    }
    
    headers = {
      "Accept" => "application/json"
    }
    
    response = HTTParty.get(url, query: query, headers: headers)
    
    response.parsed_response
  end

  def self.sync
    loop do
      latest_block_number = EthBlock.maximum(:block_number) || 0
      next_block_number = latest_block_number + 1
      
      response = fetch_ethscriptions(next_block_number)
      
      if response.dig('error', 'resolution') == 'retry'
        return
      elsif response['error']
        raise "Unexpected error: #{response['error']}"
      end
      
      api_first_block = response['blocks'].first
      our_previous_block = EthBlock.find_by(block_number: api_first_block['block_number'] - 1)
      
      if our_previous_block
        if our_previous_block.blockhash != api_first_block['parent_blockhash']
          our_previous_block.destroy!
          Rails.logger.warn "Deleted block #{our_previous_block.block_number} because it had a different parent blockhash"
          return
        end
      else
        if EthBlock.count > 0
          raise "Missing previous block"
        end
      end
      
      response['blocks'].each do |block|
        EthBlock.transaction do
          eth_block = EthBlock.create!(
            block_number: block['block_number'],
            blockhash: block['blockhash'],
            parent_blockhash: block['parent_blockhash'],
            timestamp: block['timestamp'],
            imported_at: Time.current
          )
      
          eth_block.import_ethscriptions(block['ethscriptions'])
        end
      end
      
      if Integer(response['total_future_ethscriptions']) == 0
        break
      end
      
      sleep(0.5)
    end
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
    
    begin
      response = query_api("ethscription_as_of",
        ethscription_id: ethscription_id,
        as_of_ethscription: as_of
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