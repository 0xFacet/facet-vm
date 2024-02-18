class StatusController < ApplicationController
  def vm_status
    expires_in(1.minute, "s-maxage": 1.minute, public: true)
    
    resp = Rails.cache.fetch("vm_status", expires_in: 6.seconds) do
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
        pending_block_count: EthBlock.pending.count,
        core_indexer_status: core_indexer_status,
      }
    end
            
    render json: numbers_to_strings(resp)
  end
end
