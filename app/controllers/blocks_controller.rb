class BlocksController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    scope = EthBlock.order(block_number: :desc)
    
    cache_key = ["blocks_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      res = scope.page(page).per(per_page).to_a
      convert_int_to_string(res)
    end
  
    render json: {
      result: result
    }
  end

  def show
    eth_block = EthBlock.find_by(block_number: params[:id])

    if eth_block.blank?
      render json: { error: "Block not found" }, status: 404
      return
    end

    render json: {
      result: convert_int_to_string(eth_block)
    }
  end

  def total
    total_blocks = EthBlock.count

    render json: {
      result: convert_int_to_string(total_blocks)
    }
  end
end
