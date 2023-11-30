class NameRegistriesController < ApplicationController
  def owned_by_address
    registry_contract = params[:registry_contract]&.downcase
    owner = params[:owner]&.downcase
    
    contract = Contract.find_by_address(registry_contract)
    impl = contract.fresh_implementation_with_current_state
    state = contract.current_state
    
    token_ids_owned_by_address = state["_ownerOf"].select do |token_id, _owner|
      _owner == owner.downcase
    end.select do |token_id, owner|
      expiry_time = state['tokenExpiryTimes'][token_id]
      expiry_time.to_i > Time.zone.now.to_i
    end.keys.map(&:to_i)
    
    tx = ContractTransaction.new(
      block_timestamp: Time.zone.now.to_i
    )
    
    tx.with_global_context do
      cards = token_ids_owned_by_address.map do |token_id|
        html_string = impl.renderCard(token_id)
        
        json_string = html_string.value.split("window.s = ")[1].
          split("document.open()")[0].strip.sub(/;\z/, '')
        
        JSON.parse(json_string)
      end
      
      render json: cards
    end
  end
end
