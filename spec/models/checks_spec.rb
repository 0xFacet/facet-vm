require 'rails_helper'

describe 'Checks' do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  
  before(:all) do
    update_supported_contracts(
      'Checks',
    )
  end
  
  it 'does it' do
    dep = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: nil,
        data: {
          type: "Checks",
          args: {
            name: "Checks",
            symbol: "CHK",
          }
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: dep.address,
        data: {
          function: "mint",
          args: 9
        }
      }
    )
    
    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: dep.address,
        data: {
          function: "burnChecks",
          args: {
            tokenIdsToBurn: [1,2,3,4,5,6],
            tokenIdToEnhance: 0
          }
        }
      }
    )
    
    token_uri = ContractTransaction.make_static_call(
      contract: dep.address, 
      function_name: "generateSVG", 
      function_args: { tokenId: 0 }
    )
    
    Clipboard.copy( "data:image/svg+xml;base64,#{Base64.strict_encode64(token_uri)}")
    
    token_uri = ContractTransaction.make_static_call(
      contract: dep.address, 
      function_name: "tokenURI", 
      function_args: { id: 0 }
    )
    # Clipboard.copy( token_uri)
    # puts JSON.parse(token_uri[/.*?,(.*)/, 1])['image']
  end

end