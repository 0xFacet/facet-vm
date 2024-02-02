class StatusController < ApplicationController
  def vm_status
    total_newer_ethscriptions = Rails.cache.read("total_ethscriptions_behind").to_i
    max_processed_block_number = EthBlock.max_processed_block_number
    
    blocks_behind = nil
    current_block_number = nil
    
    core_indexer_status = Rails.cache.fetch("core_indexer_status", expires_in: 5.seconds) do
      EthsIndexerClient.indexer_status
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
