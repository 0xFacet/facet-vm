class StatusController < ApplicationController
  def vm_status
    expires_in 1.second, public: true
    
    total_newer_ethscriptions = Rails.cache.read("total_ethscriptions_behind").to_i
        
    resp = {
      ethscriptions_behind: total_newer_ethscriptions,
      max_processed_block_number: EthBlock.max_processed_block_number,
    }
        
    render json: convert_int_to_string(resp)
  end
end
