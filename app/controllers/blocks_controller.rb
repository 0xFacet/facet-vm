class BlocksController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    scope = EthBlock.includes(:ethscriptions).order(block_number: :desc)
    
    cache_key = ["blocks_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      scope.page(page).per(per_page).to_a
    end
  
    render json: {
      result: result
    }
  end

  def show
    eth_block = EthBlock.includes(:ethscriptions).find_by(block_number: params[:block_number])

    if eth_block.blank?
      render json: { error: "Block not found" }, status: 404
      return
    end

    render json: {
      result: eth_block
    }
  end

  def total
    total_blocks = EthBlock.count

    render json: {
      result: total_blocks
    }
  end
end
