class ContractCallsController < ApplicationController
  cache_actions_on_block
  
  def index
    scope = cursor_mode? ? ContractCall.all : ContractCall.newest_first
    
    scope = filter_by_params(scope,
      :transaction_hash,
      :effective_contract_address
    )
    
    if params[:to_or_from].present?
      to_or_from = params[:to_or_from].downcase
      scope = scope.where(
        "from_address = :addr OR effective_contract_address = :addr",
        addr: to_or_from
      )
    end
    
    if cursor_mode?
      render_paginated_json(scope)
    else
      page, per_page = v1_page_params
      
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
end
