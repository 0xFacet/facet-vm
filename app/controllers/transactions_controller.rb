class TransactionsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    scope = ContractTransactionReceipt.newest_first
    
    cache_key = ["transactions_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      scope.page(page).per(per_page).to_a
    end
  
    render json: {
      result: result
    }
  end

  def show
    transaction = ContractTransactionReceipt.find_by(transaction_hash: params[:id])

    if transaction.blank?
      render json: { error: "Transaction not found" }, status: 404
      return
    end

    render json: {
      result: transaction
    }
  end

  def total
    total_transactions = ContractTransactionReceipt.count

    render json: {
      result: total_transactions
    }
  end
end
