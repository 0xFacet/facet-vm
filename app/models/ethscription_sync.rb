class EthscriptionSync
  include HTTParty
  # base_uri 'https://api.goerli-ethscriptions.com/api/ethscriptions'

  def fetch_newer_ethscriptions(latest_ethscription_id, page = 1, per_page = 25)
    # url = "https://api.goerli-ethscriptions.com/api/ethscriptions/newer_ethscriptions"
    url = "http://localhost:4000/api/ethscriptions/newer_ethscriptions"
    
    query = {
      ethscription_id: latest_ethscription_id,
      mimetypes: [
        "application/vnd.esc.contract.call+json",
        "application/vnd.esc.contract.deploy+json"
      ],
      page: page,
      per_page: per_page
    }
    
    headers = {
      "Accept" => "application/json"
    }
    
    response = HTTParty.get(url, query: query, headers: headers)
    response.parsed_response['ethscriptions'].map do |eth|
      transform_server_response(eth)
    end
  end

  def self.s
    new.sync
  end
  
  def sync
    # Ethscription.delete_all
    page = 1
    per_page = 25
    
    loop do
      local_latest_ethscription = Ethscription.newest_first.first

      response = fetch_newer_ethscriptions(
        local_latest_ethscription&.ethscription_id, page, per_page
      )
      
      ActiveRecord::Base.transaction do
        starting_ethscription = Ethscription.find_by(
          ethscription_id: response.first[:ethscription_id]
        )
        
        starting_ethscription&.delete_with_later_ethscriptions
        
        sorted_response = response.sort_by do |e|
          [e[:block_number], e[:transaction_index]]
        end
  
        sorted_response.each do |ethscription_data|
          Ethscription.create!(ethscription_data)
        end
      end
      
      break if response.length < per_page
      page += 1
      
      sleep(1)
    end
  end
  
  def transform_server_response(server_data)
    res = {
      ethscription_id: server_data['transaction_hash'],
      block_number: server_data['block_number'],
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
$s = EthscriptionSync