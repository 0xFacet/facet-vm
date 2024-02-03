module EthsIndexerClient
  def self.base_url
    ENV.fetch("INDEXER_API_BASE_URI")
  end
  
  def self.indexer_status
    url = "#{base_url}/status"
    make_request(url, {}, timeout: 2)
  end
  
  def self.newer_ethscriptions(**kwargs)
    url = "#{base_url}/ethscriptions/newer_ethscriptions"
    make_request(url, kwargs)
  end
  
  def self.newer_blocks(**kwargs)
    url = "#{base_url}/blocks/newer_blocks"
    make_request(url, kwargs)
  end
  
  def self.fetch_ethscription_transfers(**kwargs)
    url = "#{base_url}/ethscription_transfers"
    make_request(url, kwargs)
  end
  
  def self.fetch_ethscriptions(**kwargs)
    url = "#{base_url}/ethscriptions"
    make_request(url, kwargs)
  end
  
  def self.bearer_token
    ENV['INTERNAL_API_BEARER_TOKEN']
  end
  
  def self.make_request(url, query = {}, method: :get, post_body: nil, timeout: 15)
    headers = {}
    headers['Authorization'] = "Bearer #{bearer_token}" if bearer_token
    
    res = begin
      response = HTTParty.send(method, url, { query: query, headers: headers, timeout: timeout, body: post_body }.compact)
      
      if response.code.between?(500, 599)
        raise HTTParty::ResponseError.new(response)
      end
      
      response.parsed_response
    rescue Timeout::Error
      { error: "Not responsive after #{timeout} seconds" }
    rescue ArgumentError => e
      { error: e.message }
    end
    
    res.with_indifferent_access
  end
end
