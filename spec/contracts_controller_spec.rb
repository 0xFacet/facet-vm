require 'rails_helper'

RSpec.describe ContractsController, type: :controller do
  describe 'GET #simulate_transaction' do
    it 'simulates success' do
      command = 'deploy'
      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        "protocol": "PublicMintERC20",
        "constructorArgs": {
          "name": "My Fun Token",
          "symbol": "FUN",
          "maxSupply": "21000000",
          "perMintLimit": "1000",
          "decimals": 18
        },
      }

      get :simulate_transaction, params: {
        command: command,
        from: from,
        data: data.to_json
      }
      
      parsed = JSON.parse(response.body)
      
      expect(parsed['result']['status']).to eq('success')
      
      expect(response).to have_http_status(:success)
    end
    
    it 'simulates failure' do
      command = 'deploy'
      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        "protocol": "PublicMintERC20",
        "constructorArgs": {
          "name": "My Fun Token",
          "symbol": "FUN",
          "maxSupply": "21000000",
          "perMintLimit": "1000",
          "decimals": -18
        },
      }

      get :simulate_transaction, params: {
        command: command,
        from: from,
        data: data.to_json
      }
      
      parsed = JSON.parse(response.body)
      
      expect(parsed['result']['status']).to eq('deploy_error')
      
      expect(response).to have_http_status(:success)
    end
  end
end
