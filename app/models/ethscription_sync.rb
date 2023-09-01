class EthscriptionSync
  include ContractErrors

  def self.query_api(url, query = {})
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/ethscriptions/" + url
    
    headers = {
      "Accept" => "application/json"
    }
    
    HTTParty.get(url, query: query, headers: headers)
  end
  
  def self.fetch_newer_ethscriptions(latest_ethscription_id, per_page = 25)
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/ethscriptions/newer_ethscriptions"
    
    query = {
      ethscription_id: latest_ethscription_id,
      mimetypes: [
        "application/vnd.esc.contract.call+json",
        "application/vnd.esc.contract.deploy+json"
      ],
      per_page: per_page
    }
    
    headers = {
      "Accept" => "application/json"
    }
    
    response = HTTParty.get(url, query: query, headers: headers)
    
    response.parsed_response
  end

  def self.local_latest_ethscription
    Ethscription.newest_first.first
  end
  
  def self.sync
    per_page = 50
    
    loop do
      parsed_response = fetch_newer_ethscriptions(
        local_latest_ethscription&.ethscription_id, per_page
      )
      
      ethscriptions = parsed_response['ethscriptions'].map do |eth|
        transform_server_response(eth)
      end
      
      starting_ethscription = Ethscription.find_by(
        ethscription_id: ethscriptions.first[:ethscription_id]
      )
      
      starting_ethscription&.delete_with_later_ethscriptions
      
      sorted_response = ethscriptions.sort_by do |e|
        [e[:block_number], e[:transaction_index]]
      end

      sorted_response.each do |ethscription_data|
        Ethscription.create!(ethscription_data)
      end
      
      break if parsed_response['total_newer_ethscriptions'].to_i == 0
      
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