class ContractCallsController < ApplicationController
  cache_actions_on_block
  
  def index
    scope = filter_by_params(ContractCall.all,
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
    
    render_paginated_json(scope)
  end
end
