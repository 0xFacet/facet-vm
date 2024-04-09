Rails.application.routes.draw do
  def draw_routes
    resources :contracts, only: [:index, :show] do
      collection do
        get "/:address/static-call/:function", to: "contracts#static_call", constraints: { address: /(0x)?[a-zA-Z0-9]{40}/ }
        get "/:address/storage-get/:first_key", to: "contracts#storage_get", constraints: { address: /(0x)?[a-zA-Z0-9]{40}/ }
        get "/transactions/:id", to: "transactions#show", constraints: { id: /(0x)?[a-zA-Z0-9]{64}/ }
        get "/simulate", to: "contracts#simulate_transaction"
        post "/simulate", to: "contracts#simulate_transaction"

        get "/all-abis", to: "contracts#all_abis"
        get "/supported-contract-artifacts", to: "contracts#supported_contract_artifacts"
        get "/deployable-contracts", to: "contracts#deployable_contracts"


        get "/pairs_with_tokens/:router", to: "contracts#pairs_with_tokens"
        get "/pairs_for_router/", to: "contracts#pairs_for_router"
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

    resources :tokens, only: [] do
      collection do
        get '/:address/get_allowance', to: 'tokens#get_allowance'
        get '/:address/historical_token_state', to: 'tokens#historical_token_state'
        get '/:address/holders', to: 'tokens#holders'
        get '/:address/swaps', to: 'tokens#swaps'
        get '/:address/volume', to: 'tokens#volume'
        get '/token_prices', to: 'tokens#token_prices'
      end
    end

    resources :wallets, only: [] do
      collection do
        get '/:address/tokens', to: 'wallets#get_tokens'
        get '/:address/token_allowances', to: 'wallets#get_token_allowances'
        get '/:address/nft_balances', to: 'wallets#get_nft_balances'
        get '/:address/nft_approvals', to: 'wallets#get_nft_approvals'
        get '/:address/pnl', to: 'wallets#pnl'
      end
    end

    resources :contract_calls, only: [:index] do
    end

    get "/status", to: "status#vm_status"
  end

  draw_routes

  scope '/v2', defaults: { api_version: '2' } do
    draw_routes
  end
end
