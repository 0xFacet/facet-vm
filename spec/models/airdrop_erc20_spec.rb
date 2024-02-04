require 'rails_helper'

RSpec.describe Contract, type: :model do
  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97" }
  let(:trusted_address) { "0x019824B229400345510A3a7EFcFB77fD6A78D8d0" }

  before do
    @creation_receipt_airdrop_erc20 = trigger_contract_interaction_and_expect_success(
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
  end

  describe ".call_contract_from_ethscription_if_needed!" do
    before do
      @mint_receipt = trigger_contract_interaction_and_expect_success(
        command: 'call',
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        data: {
          "contract": @creation_receipt_airdrop_erc20.address,
          "functionName": "airdrop",
          "args": ["0xC2172a6315c1D7f6855768F843c420EbB36eDa97","5"],
        }
      )
    end

    it "won't call constructor after deployed (airdrop)" do
      trigger_contract_interaction_and_expect_call_error(
        command: 'call',
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        data: {
          "contract": @creation_receipt_airdrop_erc20.address,
          "functionName": "constructor",
          "args": {
            "name": "My Fun Token",
            "symbol": "FUN",
            "owner": "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
          },
        }
      )
    end

   it "will simulate a deploy transaction for airdrop ERC20" do
      transpiled = RubidityTranspiler.transpile_file("AirdropERC20")
      item = transpiled.detect{|i| i.name.to_s == "AirdropERC20"}

      from = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"
      data = {
        op: :create,
        data: {
          source_code: item.source_code,
          init_code_hash: item.init_code_hash,
          args: {
            "name": "My Fun Token",
            "symbol": "FUN",
            "owner": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
            "maxSupply": "21000000",
            "perMintLimit": "1000",
            "decimals": 18
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
      resp = ContractTransaction.simulate_transaction(
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        tx_payload: {
          op: "call",
          data: {
            "to": @creation_receipt_airdrop_erc20.address,
            "function": "airdrop",
            "args": {
              "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
              "amount": "5"
            }
          }
        }
      )

      call_receipt_success = resp['transaction_receipt']

      expect(call_receipt_success).to be_a(TransactionReceipt)
      expect(call_receipt_success.status).to eq("success")

      expect(Ethscription.find_by(transaction_hash: call_receipt_success.transaction_hash)).to be_nil

      expect(@creation_receipt_airdrop_erc20.contract.states.count).to eq(2)
   end

   it "will make an actual call to deploy and to airdrop" do
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
            ["5","10"]
          ]
        }
      )

        expect(deploy.contract.states.count).to eq(2)
    end

   it "will simulate a call to check airdrop limits max per mint" do
      resp = ContractTransaction.simulate_transaction(
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        tx_payload: {
          op: :call,
          data: {
            "to": @creation_receipt_airdrop_erc20.address,
            "function": "airdrop",
            "args": {
              "to": "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
              "amount": "5000"
            },
          }
        }
      )

      call_receipt_fail = resp['transaction_receipt']

      expect(call_receipt_fail).to be_a(TransactionReceipt)
      expect(call_receipt_fail.status).to eq("failure")

      expect(Ethscription.find_by(transaction_hash: call_receipt_fail.transaction_hash)).to be_nil

      expect(@creation_receipt_airdrop_erc20.contract.states.count).to eq(2)
   end

    it "will simulate a call to check multiple airdrop upper limit per mint" do
      resp = ContractTransaction.simulate_transaction(
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        tx_payload: {
          op: :call,
          data: {
            "to": @creation_receipt_airdrop_erc20.address,
            "function": "airdropMultiple",
            "args": {
               "addresses": ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
               "amounts": ["5000","10000"]
            },
          }
        }
      )

      call_receipt_fail = resp['transaction_receipt']

      expect(call_receipt_fail).to be_a(TransactionReceipt)
      expect(call_receipt_fail.status).to eq("failure")

      expect(Ethscription.find_by(transaction_hash: call_receipt_fail.transaction_hash)).to be_nil

      expect(@creation_receipt_airdrop_erc20.contract.states.count).to eq(2)
  end

  it "will make a multiple airdrop and simulate burning those tokens afterwards thereby proving balance distribution" do
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
          ["5","10"]
        ]
      }
    )

    resp = ContractTransaction.simulate_transaction(
      from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
      tx_payload: {
        op: "call",
        data: {
          "to": deploy.address,
          "function": "burn",
          "args": {
            "amount": "5"
          }
        }
      }
    )

    call_receipt_success = resp['transaction_receipt']

    expect(call_receipt_success).to be_a(TransactionReceipt)
    expect(call_receipt_success.status).to eq("success")

    expect(Ethscription.find_by(transaction_hash: call_receipt_success.transaction_hash)).to be_nil

    resp = ContractTransaction.simulate_transaction(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      tx_payload: {
        op: "call",
        data: {
          "to": deploy.address,
          "function": "burn",
          "args": {
            "amount": "10"
          }
        }
      }
    )

      call_receipt_success = resp['transaction_receipt']

      expect(call_receipt_success).to be_a(TransactionReceipt)
      expect(call_receipt_success.status).to eq("success")

      expect(Ethscription.find_by(transaction_hash: call_receipt_success.transaction_hash)).to be_nil

      resp = ContractTransaction.simulate_transaction(
        from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
        tx_payload: {
          op: :call,
          data: {
            "to": deploy.address,
            "function": "burn",
            "args": {
               "amount": "12"
            },
          }
        }
      )

      call_receipt_fail = resp['transaction_receipt']

      expect(call_receipt_fail).to be_a(TransactionReceipt)
      expect(call_receipt_fail.status).to eq("failure")

      expect(Ethscription.find_by(transaction_hash: call_receipt_fail.transaction_hash)).to be_nil

      expect(deploy.contract.states.count).to eq(2)
   end

   it "will simulated an airdrop up to 10 addresses" do
      resp = ContractTransaction.simulate_transaction(
        from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
        tx_payload: {
          op: :call,
          data: {
            "to": @creation_receipt_airdrop_erc20.address,
            "function": "airdropMultiple",
            "args": {
               "addresses": ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"] * 5,
               "amounts": ["5","10"] * 5
            },
          }
        }
      )

      call_receipt_fail = resp['transaction_receipt']

      expect(call_receipt_fail).to be_a(TransactionReceipt)
      expect(call_receipt_fail.status).to eq("success")

      expect(Ethscription.find_by(transaction_hash: call_receipt_fail.transaction_hash)).to be_nil

      expect(@creation_receipt_airdrop_erc20.contract.states.count).to eq(2)
   end

   it "wont airdrop above upper limit of 10 addresses" do
    trigger_contract_interaction_and_expect_error(
      command: 'call',
      from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
      payload: {
        "to": @creation_receipt_airdrop_erc20.address,
        data: {
          "function": "airdropMultiple",
          "args": {
            "addresses": ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"] * 6,
            "amounts": ["5","10"] * 6
          },
        }
      }
    )
    
    resp = ContractTransaction.simulate_transaction(
      from: "0x019824B229400345510A3a7EFcFB77fD6A78D8d0",
      tx_payload: {
        op: :call,
        data: {
          "to": @creation_receipt_airdrop_erc20.address,
          "function": "airdropMultiple",
          "args": {
              "addresses": ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"] * 6,
              "amounts": ["5","10"] * 6
          },
        }
      }
    )

    call_receipt_fail = resp['transaction_receipt']

    expect(call_receipt_fail).to be_a(TransactionReceipt)
    expect(call_receipt_fail.status).to eq("failure")

    expect(Ethscription.find_by(transaction_hash: call_receipt_fail.transaction_hash)).to be_nil

    expect(@creation_receipt_airdrop_erc20.contract.states.count).to eq(2)
   end

   it "airdrop multiple wont be called without owner perms" do
    trigger_contract_interaction_and_expect_error(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      payload: {
        "to": @creation_receipt_airdrop_erc20.address,
        data: {
          "function": "airdropMultiple",
          "args": {
            "addresses": ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
            "amounts": ["5","10"]
          },
        }
      }
    )
    
    resp = ContractTransaction.simulate_transaction(
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      tx_payload: {
        op: :call,
        data: {
          "to": @creation_receipt_airdrop_erc20.address,
          "function": "airdropMultiple",
          "args": {
            "addresses": ["0x019824B229400345510A3a7EFcFB77fD6A78D8d0","0xC2172a6315c1D7f6855768F843c420EbB36eDa97"],
            "amounts": ["5","10"]
          },
        }
      }
    )

    call_receipt_fail = resp['transaction_receipt']

    expect(call_receipt_fail).to be_a(TransactionReceipt)
    expect(call_receipt_fail.status).to eq("failure")

    expect(Ethscription.find_by(transaction_hash: call_receipt_fail.transaction_hash)).to be_nil

    expect(@creation_receipt_airdrop_erc20.contract.states.count).to eq(2)
   end
  end
end
