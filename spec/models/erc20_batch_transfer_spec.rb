require 'rails_helper'

RSpec.describe Contract, type: :model do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:trusted_address) { "0x019824B229400345510A3a7EFcFB77fD6A78D8d0" }
  let(:alice_key) { Eth::Key.new(priv: "0" * 63 + "1") }
  let(:alice) { alice_key.address.address }
  let(:bob) { "0x000000000000000000000000000000000000000b" }
  let(:charlie) { "0x000000000000000000000000000000000000000c" }
  let(:daryl) { "0x000000000000000000000000000000000000000d" }

  before(:all) do
    update_supported_contracts("ERC20BatchTransfer")
  end

  before do
    @creation_receipt_multi_sender_erc20 = trigger_contract_interaction_and_expect_success(
      command: 'deploy',
      from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
      data: {
        "protocol": "ERC20BatchTransfer",
        "constructorArgs": {
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
              "protocol": "ERC20BatchTransfer",
              "constructorArgs": {
              },
            }
      )
    end

    it "won't call constructor after deployed (batch transferer)" do
      trigger_contract_interaction_and_expect_call_error(
        command: 'call',
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        data: {
          "contract": @creation_receipt_multi_sender_erc20.address,
          "functionName": "constructor",
          "args": {
          },
        }
      )
    end

   it "will simulate a deploy transaction for batch transferer ERC20" do
      transpiled = RubidityTranspiler.transpile_file("ERC20BatchTransfer")
      item = transpiled.detect{|i| i.name.to_s == "ERC20BatchTransfer"}

      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        op: :create,
        data: {
          source_code: item.source_code,
          init_code_hash: item.init_code_hash,
          args: {
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

    it "will simulate a call to check batch transferer is working" do
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
            "function": "batchTransfer",
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

   it "will make an actual call to deploy and to batch transfer" do
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

    batchTransfer = trigger_contract_interaction_and_expect_success(
            command: 'call',
            from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
            data: {
              "contract": @creation_receipt_multi_sender_erc20.address,
              functionName: "batchTransfer",
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

        expect(batchTransfer.contract.states.count).to eq(1)
        end


   it "will fail to batch transfer with insufficient balance" do
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
              "function": "batchTransfer",
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

   it "will fail to batch transfer with insufficient allowance" do
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
              "function": "batchTransfer",
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

   it "will fail to batch transfer with too many wallets" do
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
              "function": "batchTransfer",
              "args": [deploy.address,
                                      ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"] * 26,
                                      ["5","5"] * 26
              ],
            }
          }
        )

        call_receipt_fail = resp['transaction_receipt']

        expect(call_receipt_fail).to be_a(TransactionReceipt)
        expect(call_receipt_fail.status).to eq("failure")
        end

   it "will fail to batch transfer with non matching array lengths" do
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
              "function": "batchTransfer",
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


   it "will make an actual call to withdraw mistaken funds" do
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

    withdraw = trigger_contract_interaction_and_expect_success(
            command: 'call',
            from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
            data: {
              "contract": @creation_receipt_multi_sender_erc20.address,
              functionName: "withdrawStuckTokens",
              args: [
                deploy.address, '0x019824B229400345510A3a7EFcFB77fD6A78D8d0', "10"
                ]
            }
          )

          erc20_balance = ContractTransaction.make_static_call(
            contract: deploy.address,
            function_name: "balanceOf",
            function_args: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0"
          )

          expect(erc20_balance).to eq(10)

        expect(withdraw.contract.states.count).to eq(1)
        end
        
        
   it "will make an actual call to deploy and to batch transfer" do
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
         ["101","10"]
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

    batchTransfer = trigger_contract_interaction_and_expect_success(
            command: 'call',
            from: '0x019824B229400345510A3a7EFcFB77fD6A78D8d0',
            data: {
              "contract": @creation_receipt_multi_sender_erc20.address,
              functionName: "batchTransfer",
              args: [deploy.address,
                [alice, bob, charlie, daryl],
                ["10","20","30","40"]
              ]
            }
          )

          expect(ContractTransaction.make_static_call(
                             contract: deploy.address,
                             function_name: "balanceOf",
                             function_args: alice
                           )).to eq(10)

          expect(ContractTransaction.make_static_call(
                             contract: deploy.address,
                             function_name: "balanceOf",
                             function_args: bob
                           )).to eq(20)

          expect(ContractTransaction.make_static_call(
                             contract: deploy.address,
                             function_name: "balanceOf",
                             function_args: charlie
                           )).to eq(30)

          expect(ContractTransaction.make_static_call(
                             contract: deploy.address,
                             function_name: "balanceOf",
                             function_args: daryl
                           )).to eq(40)


        expect(batchTransfer.contract.states.count).to eq(1)
        end
    end
end
