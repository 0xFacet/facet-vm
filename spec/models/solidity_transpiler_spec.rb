require 'rails_helper'

RSpec.describe "Solidity Transpiler" do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  before(:each) do
    allow_any_instance_of(SystemConfigVersion).to receive(:contract_supported?).and_return(true)
  end
  
  it "should transpile solidity code to rubidity code" do
    filename = Rails.root.join('app/models/contracts/AirdropERC20.sol')
    contract_name = "AirdropERC20"
    transpiler = SolidityToRubidityTranspiler.new(filename, contract_name)
    
    ruby_code = transpiler.transpile
    
    item = RubidityTranspiler.new(ruby_code).generate_contract_artifact_json
    # binding.pry
    
    deploy = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
      data: {
        op: :create,
        data: {
          contract_artifact: item,
          args: {
            "name": "My Fun Token",
            "symbol": "FUN",
            "owner": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            "maxSupply_": "21000000",
            "perMintLimit_": "1000",
            "decimals_": 18
          }
        }
      }
    )
    
    binding.pry
  end
end