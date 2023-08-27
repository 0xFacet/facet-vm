require 'rails_helper'

RSpec.describe Contract, type: :model do
  before do
    ENV['INDEXER_API_BASE_URI'] = "http://localhost:4000/api"
    
    @creation_receipt = ContractTestHelper.trigger_contract_interaction(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "OpenMintToken",
        "constructorArgs": {
          "name": "My Fun Token",
          "symbol": "FUN",
          "maxSupply": "21000000",
          "perMintLimit": "1000",
          "decimals": 18
        },
      }
    )
  end

  describe ".deploy_new_contract_from_ethscription_if_needed!" do
    it "creates a new contract" do
      expect(@creation_receipt.status).to eq("success")
    end
  end

  describe ".call_contract_from_ethscription_if_needed!" do
    before do
      @mint_receipt = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "mint",
          "args": {
            "amount": "5"
          },
        }
      )
    end
    
    it "won't call constructor after deployed" do
      r = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "constructor",
          "args": {
            "name": "My Fun Token",
            "symbol": "FUN",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      )
      
      expect(r.status).to eq("call_error")
    end
    
    it "won't static call restricted function" do
      expect {
        ContractTransaction.make_static_call(
          contract_id: @mint_receipt.contract.contract_id,
          function_name: "id"
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    it "won't static call restricted function" do
      expect {
        ContractTransaction.make_static_call(
          contract_id: @mint_receipt.contract.contract_id,
          function_name: "_mint",
          function_args: {
            "amount": "5",
            to: "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E"
          },
        )
      }.to raise_error(Contract::StaticCallError)
    end
    
    it "mints the contract" do
      expect(@mint_receipt.status).to eq("success")
    end
    
    it "calls transfer" do
      @transfer_receipt = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "transfer",
          "args": {
            "amount": "2",
            "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
          },
        }
      )
      expect(@transfer_receipt.status).to eq("success")
    end
    
    it "airdrops" do
      @transfer_receipt = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": @creation_receipt.contract_id,
          "functionName": "airdrop",
          "args": {
            "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
            "amount": "2"
          },
        }
      )
      # pp @transfer_receipt.contract.load_current_state
      expect(@transfer_receipt.status).to eq("success")
    end
    
    # it "bridges" do
    #   trusted_address = "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
      
    #   token = ContractTestHelper.trigger_contract_interaction(
    #     command: 'deploy',
    #     from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
    #     data: {
    #       "protocol": "BridgeableToken",
    #       constructorArgs: {
    #         _name: "Bridge Native 1",
    #         _symbol: "PT1",
    #         _trusted_smart_contract: trusted_address
    #       }
    #     }
    #   ).contract
      
    #   ContractTestHelper.trigger_contract_interaction(
    #     command: 'call',
    #     from: trusted_address,
    #     data: {
    #       "contractId": token.contract_id,
    #       functionName: "bridge_in",
    #       args: {
    #         to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
    #         amount: 500,
    #       }
    #     }
    #   )
      
    #   ContractTestHelper.trigger_contract_interaction(
    #     command: 'call',
    #     from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
    #     data: {
    #       "contractId": token.contract_id,
    #       functionName: "bridge_out",
    #       args: {
    #         amount: 100,
    #       }
    #     }
    #   )
      
    #   balance = token.static_call(
    #     function_name: "balance_of",
    #     args: {
    #       address: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
    #     }
    #   )
      
    #   expect(balance).to eq(400)
      
    #   ContractTestHelper.trigger_contract_interaction(
    #     command: 'call',
    #     from: trusted_address,
    #     data: {
    #       "contractId": token.contract_id,
    #       functionName: "mark_withdrawal_complete",
    #       args: {
    #         address: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
    #         amount: 100,
    #       }
    #     }
    #   )
    # end
    
    it "dexes" do
      token_0 = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "OpenMintToken",
          "constructorArgs": {
            "name": "Pool Token 1",
            "symbol": "PT1",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      ).contract
      
      token_1 = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "OpenMintToken",
          "constructorArgs": {
            "name": "Pool Token 2",
            "symbol": "PT2",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      ).contract
      
      dex = ContractTestHelper.trigger_contract_interaction(
        command: 'deploy',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "protocol": "DexLiquidityPool",
          constructorArgs: {
            token0: token_0.contract_id,
            token1: token_1.contract_id
          }
        }
      ).contract
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_0.contract_id,
          functionName: "mint",
          args: {
            amount: 500
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_1.contract_id,
          functionName: "mint",
          args: {
            amount: 600
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_1.contract_id,
          functionName: "approve",
          args: {
            spender: dex.contract_id,
            value: (21e6).to_i
          }
        }
      )
      
      ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": token_0.contract_id,
          functionName: "approve",
          args: {
            spender: dex.contract_id,
            value: (21e6).to_i
          }
        }
      )
      
      add_liq = ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xc2172a6315c1d7f6855768f843c420ebb36eda97",
        data: {
          "contractId": dex.contract_id,
          functionName: "add_liquidity",
          args: {
            token_0_amount: 200,
            token_1_amount: 100
          }
        }
      )
      
      expect(add_liq.status).to eq("success")
      
      a = ContractTransaction.make_static_call(
        contract_id: token_0.contract_id,
        function_name: "balanceOf",
        function_args: {
          _1: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
# binding.pry
      expect(a).to eq(300)
      
      pp ContractTestHelper.trigger_contract_interaction(
        command: 'call',
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        data: {
          "contractId": dex.contract_id,
          functionName: "swap",
          args: {
            input_amount: 50,
            output_token: token_1.contract_id,
            input_token: token_0.contract_id,
          }
        }
      )
      
      final_token_a_balance = ContractTransaction.make_static_call(
        contract_id: token_0.contract_id,
        function_name: "balanceOf",
        function_args: {
          _1: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
      
      expect(final_token_a_balance).to eq(250)
      
      final_token_b_balance = ContractTransaction.make_static_call(
        contract_id: token_1.contract_id,
        function_name: "balanceOf",
        function_args: {
          _1: "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
        }
      )
      
      expect(final_token_b_balance).to be > 500
      
      calculate_output_amount = ContractTransaction.make_static_call(
        contract_id: dex.contract_id,
        function_name: "calculate_output_amount",
        function_args: {
          input_token: token_0.contract_id,
          output_token: token_1.contract_id,
          input_amount: 50
        }
      )
    end
  end
end
