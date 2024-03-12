class BlocksController < ApplicationController
  cache_actions_on_block

  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    scope = if system_start_block.present?
      EthBlock.where("block_number >= ?", system_start_block).
        processed.
        order(block_number: :desc)
    else
      EthBlock.none
    end
    
    cache_key = ["blocks_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      res = scope.page(page).per(per_page).to_a
      numbers_to_strings(res)
    end
  
    render json: {
      result: result
    }
  end

  def show
    scope = if system_start_block.present?
      EthBlock.where("block_number >= ?", system_start_block).
        processed.
        where(block_number: params[:id])
    else
      EthBlock.none
    end
    
    eth_block = scope.first

    if eth_block.blank?
      render json: { error: "Block not found" }, status: 404
      return
    end

    render json: {
      result: numbers_to_strings(eth_block)
    }
  end

  def total
    total_blocks = if system_start_block.present?
      EthBlock.processed.where("block_number >= ?", system_start_block).count
    else
      0
    end
    
    render json: {
      result: numbers_to_strings(total_blocks)
    }
  end
  
  private
  
  def system_start_block
    SystemConfigVersion.current.start_block_number
  end
end
