class StatusController < ApplicationController
  def vm_status
    total_newer_ethscriptions = Rails.cache.read("total_ethscriptions_behind").to_i
    max_processed_block_number = EthBlock.max_processed_block_number
    
    url = ENV.fetch("INDEXER_API_BASE_URI") + "/status/"
    
    blocks_behind = nil
    current_block_number = nil
    timeout = 2
    
    core_indexer_status = Rails.cache.fetch("core_indexer_status", expires_in: 5.seconds) do
      headers = {}
      
      if ENV['INTERNAL_API_BEARER_TOKEN'].present?
        headers['Authorization'] = "Bearer #{ENV['INTERNAL_API_BEARER_TOKEN']}"
      end
        
      begin
        response = HTTParty.get(url, { headers: headers, timeout: timeout }.compact)
        raise HTTParty::ResponseError.new(response) unless response.success?
        response.parsed_response
      rescue Timeout::Error
        { error: "Core indexer status not responsive after #{timeout} seconds" }
      rescue HTTParty::ResponseError => e
        { error: "HTTP Error", code: e.response.code, body: e.response.body }
      end
    end
    
    if current_block_number = core_indexer_status.delete("current_block_number")
      blocks_behind = current_block_number - max_processed_block_number
    end
    
    resp = {
      ethscriptions_behind: total_newer_ethscriptions,
      current_block_number: current_block_number,
      max_processed_block_number: max_processed_block_number,
      blocks_behind: blocks_behind,
      core_indexer_status: core_indexer_status,
    }
        
    render json: convert_int_to_string(resp)
  end
end
