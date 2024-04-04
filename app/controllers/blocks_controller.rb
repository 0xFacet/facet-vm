class BlocksController < ApplicationController
  cache_actions_on_block
  before_action :set_eth_block_scope

  def index
    results, pagination_response = paginate(@eth_block_scope)
    
    render json: {
      result: numbers_to_strings(results),
      pagination: pagination_response
    }
  end

  def show
    eth_block = @eth_block_scope.where(block_number: params[:id]).first

    raise RequestedRecordNotFound unless eth_block

    render json: { result: numbers_to_strings(eth_block) }
  end

  def total
    total_blocks = @eth_block_scope.count
    
    render json: { result: numbers_to_strings(total_blocks) }
  end
  
  private
  
  def set_eth_block_scope
    @eth_block_scope = if system_start_block.present?
                         EthBlock.processed.where("block_number >= ?", system_start_block)
                       else
                         EthBlock.none
                       end
  end

  def system_start_block
    @_system_start_block ||= SystemConfigVersion.current.start_block_number
  end
end
