Rails.application.routes.draw do
  resources :contracts, only: [:index, :show] do
    collection do
      get "/:contract_id/call-receipts/", to: "contracts#contract_call_receipts", constraints: { contract_id: /(0x)?[a-zA-Z0-9]{64}/ }
      get "/:contract_id/static-call/:function_name", to: "contracts#static_call", constraints: { contract_id: /(0x)?[a-zA-Z0-9]{64}/ }
      get "/call-receipts/:ethscription_id", to: "contracts#show_call_receipt", constraints: { transaction_hash: /(0x)?[a-zA-Z0-9]{64}/ }
      get "/simulate/:command", to: "contracts#simulate_transaction"
      
      get "/all-abis", to: "contracts#all_abis"
      get "/deployable-contracts", to: "contracts#deployable_contracts"
    end
  end
  
  get "/status", to: "status#vm_status"
end
