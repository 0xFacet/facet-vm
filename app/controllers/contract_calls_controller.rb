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
    
    cache_key = ["contract_calls_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      contract_calls = scope.page(page).per(per_page).to_a
      convert_int_to_string(contract_calls)
    end
  
    render json: {
      result: result
    }
  end
  
  def convert_int_to_string(result)
    result = result.as_json
  
    case result
    when Numeric
      result.to_s
    when Hash
      result.deep_transform_values { |value| convert_int_to_string(value) }
    when Array
      result.map { |value| convert_int_to_string(value) }
    else
      result
    end
  end
end
