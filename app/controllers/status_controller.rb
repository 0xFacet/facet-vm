class StatusController < ApplicationController
  def vm_status
    oldest_ethscription = Ethscription.oldest_first.first
    newest_ethscription = Ethscription.newest_first.first
    
    if newest_ethscription.nil?
      render json: { error: "No ethscriptions found" }
      return
    end
    
    resp = EthscriptionSync.fetch_newer_ethscriptions(newest_ethscription.ethscription_id, 1)
    
    total_newer_ethscriptions = resp['total_newer_ethscriptions'].to_i
        
    resp = {
      oldest_known_ethscription: oldest_ethscription,
      newest_known_ethscription: newest_ethscription,
      ethscriptions_behind: total_newer_ethscriptions
    }
        
    render json: resp
  end
end
