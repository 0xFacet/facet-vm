require 'rails_helper'

RSpec.describe ContractsController, type: :controller do
  describe 'GET #simulate_transaction' do
    it 'simulates success' do
      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        to: nil,
        data: {
          type: "PublicMintERC20",
          args: {
            "name": "My Fun Token",
            "symbol": "FUN",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          }
        }
      }

      get :simulate_transaction, params: {
        from: from,
        tx_payload: data.to_json
      }
      
      parsed = JSON.parse(response.body)
      
      expect(parsed.dig('result', 'status')).to eq('success')
      
      expect(response).to have_http_status(:success)
    end
    
    it 'simulates call to non-existent contract' do
      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        to: "0xe9ff6048004823961bb53d7a0629e570fe2c1c59",
        data: {
          function: "mint",
          args: {"amount":"1000000000000000000000"}
        }
      }

      get :simulate_transaction, params: {
        from: from,
        tx_payload: data.to_json
      }
      
      parsed = JSON.parse(response.body)
      
      expect(parsed.dig('result', 'status')).to eq('error')
      
      expect(response).to have_http_status(:success)
    end
    
    it 'simulates failure' do
      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        data: {
          type: "PublicMintERC20",
          args: {
            "name": "My Fun Token",
            "symbol": "FUN",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": -18
          }
        }
      }
      
      get :simulate_transaction, params: {
        from: from,
        tx_payload: data.to_json
      }
      
      parsed = JSON.parse(response.body)
      
      expect(parsed.dig('result', 'status')).to eq('error')
      
      expect(response).to have_http_status(:success)
    end
  end
  
  describe 'GET #static_call' do
    let(:contract_address) { '0x' + '1' * 40 }
    let(:function_name) { 'myFunction' }
    let(:args) { { arg1: 'value1', arg2: 'value2' } }
    let(:env) { { 'msgSender' => '0x456' } }

    before do
      allow(ContractTransaction).to receive(:make_static_call).and_return(result)
      get :static_call, params: { address: contract_address, function: function_name, args: args.to_json, env: env.to_json }
    end

    context 'when the result is an integer' do
      let(:result) { 123 }

      it 'returns the result as a string' do
        expect(JSON.parse(response.body)['result']).to eq('123')
      end
    end

    context 'when the result is a hash' do
      let(:result) { { key1: 123, key2: 456, key3: [222], key4: {key5: 123} } }

      it 'returns the result with integer values converted to strings' do
        expect(JSON.parse(response.body)['result']).to eq(
          {"key1"=>"123",
          "key2"=>"456",
          "key3"=>["222"],
          "key4"=>{"key5"=>"123"}}
        )
      end
    end

    context 'when the result is neither an integer nor a hash' do
      let(:result) { 'some string' }

      it 'returns the result as is' do
        expect(JSON.parse(response.body)['result']).to eq('some string')
      end
    end
  end
end
