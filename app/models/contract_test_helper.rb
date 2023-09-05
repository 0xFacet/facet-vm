module ContractTestHelper
  def trigger_contract_interaction_and_expect_call_error(**params)
    trigger_contract_interaction_and_expect_status(status: "call_error", **params)
  end
  
  def trigger_contract_interaction_and_expect_success(**params)
    trigger_contract_interaction_and_expect_status(status: "success", **params)
  end
  
  def trigger_contract_interaction_and_expect_deploy_error(**params)
    trigger_contract_interaction_and_expect_status(status: "deploy_error", **params)
  end
  
  def trigger_contract_interaction_and_expect_status(status:, **params)
    interaction = ContractTestHelper.trigger_contract_interaction(**params)
    expect(interaction.status).to eq(status), failure_message(interaction)
    interaction
  end
  
  def failure_message(interaction)
    test_location = caller_locations.find { |location| location.path.include?('/spec/') }
    "\nCall error: #{interaction.error_message}\nTest failed at: #{test_location}"
  end
  
  def self.dep
    @creation_receipt = ContractTestHelper.trigger_contract_interaction(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "PublicMintERC20",
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
  
  def self.trigger_contract_interaction(
    command:,
    from:,
    data:
  )
    data = data.merge(salt: SecureRandom.hex)
    
    mimetype = "data:application/vnd.esc.contract.#{command}+json"
    uri = %{#{mimetype},#{data.to_json}}
    
    tx_hash = "0x" + SecureRandom.hex(32)
    sha = Digest::SHA256.hexdigest(uri)
    
    existing = Ethscription.newest_first.first
    
    block_number = existing&.block_number.to_i + 1
    transaction_index = existing&.transaction_index.to_i + 1
    
    ethscription_attrs = {
      "ethscription_id"=>tx_hash,
      "block_number"=> block_number,
      "block_blockhash"=> "0x" + SecureRandom.hex(32),
      "current_owner"=>from.downcase,
      "creator"=>from.downcase,
      creation_timestamp: Time.zone.now,
      "initial_owner"=>'0x0000000000000000000000000000000000000000',
      "transaction_index"=>transaction_index,
      "content_uri"=> uri,
      "content_sha"=>sha,
      mimetype: mimetype
    }
    
    eth = Ethscription.create!(ethscription_attrs)
    eth.contract_call_receipt
  end
  
  def self.test_api
    creation_receipt = ContractTestHelper.trigger_contract_interaction(
      command: 'deploy',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "protocol": "PublicMintERC20",
        "constructorArgs": {
          "name": "My Fun Token",
          "symbol": "FUN",
          "maxSupply": "21000000",
          "perMintLimit": 1000,
          "decimals": 18
        },
      }
    )
    
    mint_receipt = ContractTestHelper.trigger_contract_interaction(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contractId": creation_receipt.contract_id,
        "functionName": "mint",
        "args": {
          "amount": 5
        },
      }
    )
    
    transfer_receipt = ContractTestHelper.trigger_contract_interaction(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contractId": creation_receipt.contract_id,
        "functionName": "transfer",
        "args": {
          "to": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
          "amount": 2
        },
      }
    )
    
    ContractTestHelper.trigger_contract_interaction(
      command: 'call',
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      data: {
        "contractId": creation_receipt.contract_id,
        "functionName": "approve",
        "args": {
          "spender": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
          "amount": "2"
        },
      }
    )
    
    return
    created_id = creation_receipt.contract_id
    caller_hash = mint_receipt.eth_transaction_id
    sender_hash = transfer_receipt.eth_transaction_id
    
    args = {
      address: '0xC2172a6315c1D7f6855768F843c420EbB36eDa97'
    }.to_json
    args = CGI.escape(args)
    
    
    url = "http://localhost:3002/api/contracts/#{created_id}/static-call/balance_of?args=#{args}"
    
    url2 = "http://localhost:3002/api/contracts/call-receipts/#{caller_hash}"
    url2 = "http://localhost:3002/api/contracts/call-receipts/#{sender_hash}"
    
    return [url, url2]
  end
end
CTH = ContractTestHelper unless defined?(CTH)