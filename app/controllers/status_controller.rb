class StatusController < ApplicationController
  def vm_status
    total_newer_ethscriptions = Rails.cache.read("total_ethscriptions_behind").to_i
        
    resp = {
      ethscriptions_behind: total_newer_ethscriptions
    }
        
    render json: convert_int_to_string(resp)
  end
end
