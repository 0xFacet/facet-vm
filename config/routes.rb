Rails.application.routes.draw do
  resources :contracts, only: [:index, :show] do
    collection do
      get "/:address/transactions/", to: "contracts#contract_call_receipts", constraints: { address: /(0x)?[a-zA-Z0-9]{40}/ }
      get "/:address/static-call/:function", to: "contracts#static_call", constraints: { address: /(0x)?[a-zA-Z0-9]{40}/ }
      get "/transactions/:transaction_hash", to: "contracts#show_call_receipt", constraints: { transaction_hash: /(0x)?[a-zA-Z0-9]{64}/ }
      get "/simulate", to: "contracts#simulate_transaction"
      post "/simulate", to: "contracts#simulate_transaction"
      
      get "/all-abis", to: "contracts#all_abis"
      get "/supported-contract-artifacts", to: "contracts#supported_contract_artifacts"
      get "/deployable-contracts", to: "contracts#deployable_contracts"
      
      
      get "/pairs_with_tokens/:router", to: "contracts#pairs_with_tokens"
    end
  end

  resources :name_registries, only: [] do
    collection do
      get '/owned-by-address', to: 'name_registries#owned_by_address'
    end
  end
  
  resources :blocks, only: [:index, :show] do
    collection do
      get '/total', to: 'blocks#total'
    end
  end

  resources :transactions, only: [:index, :show] do
    collection do
      get '/total', to: 'transactions#total'
    end
  end
  
  resources :contract_calls, only: [:index] do
  end
  
  get "/status", to: "status#vm_status"
end
