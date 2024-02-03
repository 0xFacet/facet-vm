class ContractCallsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    scope = ContractCall.newest_first
    
    if params[:transaction_hash]
      scope = scope.where(
        transaction_hash: params[:transaction_hash]
      )
    end
    
    if params[:effective_contract_address]
      scope = scope.where(
        effective_contract_address: params[:effective_contract_address]
      )
    end
    
    if params[:to_or_from].present?
      to_or_from = params[:to_or_from].downcase
      scope = scope.where(
        "from_address = :addr OR effective_contract_address = :addr",
        addr: to_or_from
      )
    end
    
    cache_key = ["contract_calls_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      contract_calls = scope.page(page).per(per_page).to_a
      numbers_to_strings(contract_calls)
    end
  
    render json: {
      result: result,
      count: scope.count
    }
  end
end
