class TransactionsController < ApplicationController
  cache_actions_on_block
  
  def index
    if cursor_mode?
      scope = TransactionReceipt.all
    else
      scope = TransactionReceipt.newest_first
      
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 50).to_i
      per_page = 50 if per_page > 50
      
      if page > 20
        render json: { error: "Page depth restricted to 20 for performance reasons.
          Soon we will switch to cursor-based pagination for this endpoint.
          Please contact hello@facet.org with questions".squish }, status: 400
        return
      end
    end
    
    scope = filter_by_params(scope, :block_number)
    
    if params[:from].present?
      scope = scope.where(from_address: Array.wrap(params[:from]).map(&:downcase))
    end
    
    if params[:to].present?
      scope = scope.where(effective_contract_address: Array.wrap(params[:to]).map(&:downcase))
    end
    
    if params[:to_or_from].present?
      to_or_from = Array.wrap(params[:to_or_from]).map(&:downcase)
      scope = scope.where(
        "from_address = ANY (ARRAY[:addr]) OR effective_contract_address = ANY (ARRAY[:addr])",
        addr: to_or_from
      )
    end
    
    if params[:after_block].present?
      scope = scope.where("block_number > ?", params[:after_block])
    end

    if cursor_mode?
      results, pagination_response = paginate(scope)
    
      render json: {
        result: numbers_to_strings(results),
        pagination: pagination_response
      }
    else
      render json: {
        result: numbers_to_strings(scope.page(page).per(per_page).to_a),
        count: (scope.count if page <= 10)
      }
    end
  end

  def show
    transaction = TransactionReceipt.find_by(transaction_hash: params[:id])

    if transaction.blank?
      render json: { error: "Transaction not found" }, status: 404
      return
    end

    render json: {
      result: numbers_to_strings(transaction)
    }
  end

  def total
    transaction_count = TransactionReceipt.count
    unique_from_address_count = TransactionReceipt.distinct.count(:from_address)
    
    result = {
      transaction_count: transaction_count,
      unique_from_address_count: unique_from_address_count
    }
    
    render json: {
      result: numbers_to_strings(result)
    }
  end
end
