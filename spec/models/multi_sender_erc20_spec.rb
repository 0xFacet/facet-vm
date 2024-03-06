require 'rails_helper'

RSpec.describe Contract, type: :model do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:trusted_address) { "0x019824B229400345510A3a7EFcFB77fD6A78D8d0" }

  before do
    @creation_receipt_multi_sender_erc20 = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
      data: {
        "protocol": "MultiSenderERC20",
        "constructorArgs": {
          "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
        },
      }
    )
  end

  describe ".call_contract_from_ethscription_if_needed!" do
    before do
      @mint_receipt = trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
       data: {
              "protocol": "MultiSenderERC20",
              "constructorArgs": {
                "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
              },
            }
      )
    end

    it "won't call constructor after deployed (airdrop)" do
      trigger_contract_interaction_and_expect_call_error(
        command: 'call',
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        data: {
          "contract": @creation_receipt_multi_sender_erc20.address,
          "functionName": "constructor",
          "args": {
             "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
          },
        }
      )
    end

   it "will simulate a deploy transaction for airdrop ERC20" do
      transpiled = RubidityTranspiler.transpile_file("MultiSenderERC20")
      item = transpiled.detect{|i| i.name.to_s == "MultiSenderERC20"}

      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        op: :create,
        data: {
          source_code: item.source_code,
          init_code_hash: item.init_code_hash,
          args: {
         "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
          }
        }
      }

      expect {
        resp = ContractTransaction.simulate_transaction(from: from, tx_payload: data)
        receipt = resp['transaction_receipt']

        expect(receipt).to be_a(TransactionReceipt)
        expect(receipt.status).to eq("success")
        expect(Ethscription.find_by(transaction_hash: receipt.transaction_hash)).to be_nil

      }.to_not change {
        [Contract, ContractState, Ethscription].map{|i| i.all.cache_key_with_version}
      }
    end

    it "will simulate a call to check airdrop is working" do
       deploy = trigger_contract_interaction_and_expect_success(
              command: 'deploy',
              from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
              data: {
                "protocol": "AirdropERC20",
                "constructorArgs": {
                  "name": "My Funs Token",
                  "symbol": "FUN",
                  "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                  "maxSupply": "21000000",
                  "perMintLimit": "1000",
                  "decimals": 18
                },
              }
            )

        trigger_contract_interaction_and_expect_success(
          command: 'call',
          from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
          data: {
            "contract": deploy.address,
            functionName: "airdropMultiple",
            args: [
              ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
              ["25","10"]
            ]
          }
        )
        trigger_contract_interaction_and_expect_success(
              from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
              payload: {
                to: deploy.address,
                data: {
                  function: "approve",
                  args: {
                    spender: @creation_receipt_multi_sender_erc20.address,
                    amount: (2 ** 256 - 1)
                  }
                }
              }
            )

      resp = ContractTransaction.simulate_transaction(
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        tx_payload: {
          op: "call",
          data: {
            "to": @creation_receipt_multi_sender_erc20.address,
            "function": "transferMultiple",
            "args": [deploy.address,
            ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
             ["5","10"]
            ]
          }
        }
      )

      call_receipt_success = resp['transaction_receipt']

     expect(call_receipt_success).to be_a(TransactionReceipt)
     expect(call_receipt_success.status).to eq("success")

     expect(Ethscription.find_by(transaction_hash: call_receipt_success.transaction_hash)).to be_nil

     expect(@creation_receipt_multi_sender_erc20.contract.states.count).to eq(1)
   end

   it "will make an actual call to deploy and to multi send" do
   deploy = trigger_contract_interaction_and_expect_success(
                 command: 'deploy',
                 from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                 data: {
                   "protocol": "AirdropERC20",
                   "constructorArgs": {
                     "name": "My Funs Token",
                     "symbol": "FUN",
                     "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                     "maxSupply": "21000000",
                     "perMintLimit": "1000",
                     "decimals": 18
                   },
                 }
               )

   trigger_contract_interaction_and_expect_success(
     command: 'call',
     from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
     data: {
       "contract": deploy.address,
       functionName: "airdropMultiple",
       args: [
         ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
         ["25","10"]
       ]
     }
   )
   trigger_contract_interaction_and_expect_success(
        command: 'call',
         from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
           data: {
           "contract": deploy.address,
             functionName: "approve",
             args: [
               @creation_receipt_multi_sender_erc20.address,
               1000
             ]
           }
       )

    transferMultiple = trigger_contract_interaction_and_expect_success(
            command: 'call',
            from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
            data: {
              "contract": @creation_receipt_multi_sender_erc20.address,
              functionName: "transferMultiple",
              args: [deploy.address,
                ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
                ["5","5"]
              ]
            }
          )

          erc20_balance = ContractTransaction.make_static_call(
            contract: deploy.address,
            function_name: "balanceOf",
            function_args: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
          )

          expect(erc20_balance).to eq(20)

        expect(transferMultiple.contract.states.count).to eq(1)
        end


   it "will fail to multi send with insufficient balance" do
   deploy = trigger_contract_interaction_and_expect_success(
                 command: 'deploy',
                 from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                 data: {
                   "protocol": "AirdropERC20",
                   "constructorArgs": {
                     "name": "My Funs Token",
                     "symbol": "FUN",
                     "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                     "maxSupply": "21000000",
                     "perMintLimit": "1000",
                     "decimals": 18
                   },
                 }
               )

   trigger_contract_interaction_and_expect_success(
     command: 'call',
     from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
     data: {
       "contract": deploy.address,
       functionName: "airdropMultiple",
       args: [
         ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
         ["25","10"]
       ]
     }
   )
   trigger_contract_interaction_and_expect_success(
        command: 'call',
         from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
           data: {
           "contract": deploy.address,
             functionName: "approve",
             args: [
               @creation_receipt_multi_sender_erc20.address,
               1000
             ]
           }
       )

        resp = ContractTransaction.simulate_transaction(
          from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
          tx_payload: {
            op: :call,
            data: {
              "to": @creation_receipt_multi_sender_erc20.address,
              "function": "transferMultiple",
              "args": [deploy.address,
                                      ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
                                      ["500","500"]
              ],
            }
          }
        )

        call_receipt_fail = resp['transaction_receipt']

        expect(call_receipt_fail).to be_a(TransactionReceipt)
        expect(call_receipt_fail.status).to eq("failure")
        end

   it "will fail to multi send with insufficient allowance" do
   deploy = trigger_contract_interaction_and_expect_success(
                 command: 'deploy',
                 from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                 data: {
                   "protocol": "AirdropERC20",
                   "constructorArgs": {
                     "name": "My Funs Token",
                     "symbol": "FUN",
                     "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                     "maxSupply": "21000000",
                     "perMintLimit": "1000",
                     "decimals": 18
                   },
                 }
               )

   trigger_contract_interaction_and_expect_success(
     command: 'call',
     from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
     data: {
       "contract": deploy.address,
       functionName: "airdropMultiple",
       args: [
         ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
         ["25","10"]
       ]
     }
   )

        resp = ContractTransaction.simulate_transaction(
          from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
          tx_payload: {
            op: :call,
            data: {
              "to": @creation_receipt_multi_sender_erc20.address,
              "function": "transferMultiple",
              "args": [deploy.address,
                                      ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
                                      ["5","5"]
              ],
            }
          }
        )

        call_receipt_fail = resp['transaction_receipt']

        expect(call_receipt_fail).to be_a(TransactionReceipt)
        expect(call_receipt_fail.status).to eq("failure")
        end

   it "will fail to multi send with too many wallets" do
   deploy = trigger_contract_interaction_and_expect_success(
                 command: 'deploy',
                 from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                 data: {
                   "protocol": "AirdropERC20",
                   "constructorArgs": {
                     "name": "My Funs Token",
                     "symbol": "FUN",
                     "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                     "maxSupply": "21000000",
                     "perMintLimit": "1000",
                     "decimals": 18
                   },
                 }
               )

   trigger_contract_interaction_and_expect_success(
     command: 'call',
     from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
     data: {
       "contract": deploy.address,
       functionName: "airdropMultiple",
       args: [
         ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
         ["25","10"]
       ]
     }
   )
   trigger_contract_interaction_and_expect_success(
        command: 'call',
         from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
           data: {
           "contract": deploy.address,
             functionName: "approve",
             args: [
               @creation_receipt_multi_sender_erc20.address,
               1000
             ]
           }
       )

        resp = ContractTransaction.simulate_transaction(
          from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
          tx_payload: {
            op: :call,
            data: {
              "to": @creation_receipt_multi_sender_erc20.address,
              "function": "transferMultiple",
              "args": [deploy.address,
                                      ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"] * 100,
                                      ["5","5"] * 100
              ],
            }
          }
        )

        call_receipt_fail = resp['transaction_receipt']

        expect(call_receipt_fail).to be_a(TransactionReceipt)
        expect(call_receipt_fail.status).to eq("failure")
        end

   it "will fail to multi send with non matching array lengths" do
   deploy = trigger_contract_interaction_and_expect_success(
                 command: 'deploy',
                 from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                 data: {
                   "protocol": "AirdropERC20",
                   "constructorArgs": {
                     "name": "My Funs Token",
                     "symbol": "FUN",
                     "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                     "maxSupply": "21000000",
                     "perMintLimit": "1000",
                     "decimals": 18
                   },
                 }
               )

   trigger_contract_interaction_and_expect_success(
     command: 'call',
     from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
     data: {
       "contract": deploy.address,
       functionName: "airdropMultiple",
       args: [
         ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
         ["25","10"]
       ]
     }
   )
   trigger_contract_interaction_and_expect_success(
        command: 'call',
         from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
           data: {
           "contract": deploy.address,
             functionName: "approve",
             args: [
               @creation_receipt_multi_sender_erc20.address,
               1000
             ]
           }
       )

        resp = ContractTransaction.simulate_transaction(
          from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
          tx_payload: {
            op: :call,
            data: {
              "to": @creation_receipt_multi_sender_erc20.address,
              "function": "transferMultiple",
              "args": [deploy.address,
                                      ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
                                      ["5"]
              ],
            }
          }
        )

        call_receipt_fail = resp['transaction_receipt']

        expect(call_receipt_fail).to be_a(TransactionReceipt)
        expect(call_receipt_fail.status).to eq("failure")
        end


   it "will make an actual call to withdraw multiple for dust or mistaken funds" do
   deploy = trigger_contract_interaction_and_expect_success(
                 command: 'deploy',
                 from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                 data: {
                   "protocol": "AirdropERC20",
                   "constructorArgs": {
                     "name": "My Funs Token",
                     "symbol": "FUN",
                     "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
                     "maxSupply": "21000000",
                     "perMintLimit": "1000",
                     "decimals": 18
                   },
                 }
               )

   trigger_contract_interaction_and_expect_success(
     command: 'call',
     from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
     data: {
       "contract": deploy.address,
       functionName: "airdropMultiple",
       args: [
         [@creation_receipt_multi_sender_erc20.address],
         ["10"]
       ]
     }
   )

    withdrawMultiple = trigger_contract_interaction_and_expect_success(
            command: 'call',
            from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
            data: {
              "contract": @creation_receipt_multi_sender_erc20.address,
              functionName: "withdrawMultiple",
              args: [
                [deploy.address, deploy.address],
                ["5","5"]
              ]
            }
          )

          erc20_balance = ContractTransaction.make_static_call(
            contract: deploy.address,
            function_name: "balanceOf",
            function_args: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
          )

          expect(erc20_balance).to eq(10)

        expect(withdrawMultiple.contract.states.count).to eq(1)
        end
    end
end
