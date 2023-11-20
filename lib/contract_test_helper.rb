module ContractTestHelper
  def trigger_contract_interaction_and_expect_call_error(**params)
    trigger_contract_interaction_and_expect_status(status: "failure", **params)
  end
  
  def trigger_contract_interaction_and_expect_error(**params)
    trigger_contract_interaction_and_expect_status(status: "failure", **params)
  end
  
  def trigger_contract_interaction_and_expect_success(**params)
    trigger_contract_interaction_and_expect_status(status: "success", **params)
  end
  
  def trigger_contract_interaction_and_expect_deploy_error(**params)
    trigger_contract_interaction_and_expect_status(status: "failure", **params)
  end
  
  def trigger_contract_interaction_and_expect_status(status:, **params)
    interaction = ContractTestHelper.trigger_contract_interaction(**params.except(:error_msg_includes))
    expect(interaction.status).to eq(status), failure_message(interaction)
    
    if status == "failure" && params[:error_msg_includes]
      expect(interaction.error['message']).to include(params[:error_msg_includes])
    end
    
    interaction
  end
  
  def self.set_initial_admin_address
    block_timestamp = Time.current.to_i
    from = ENV.fetch("INITIAL_SYSTEM_CONFIG_ADMIN_ADDRESS")
    mimetype = SystemConfigVersion.system_mimetype

    existing = Ethscription.newest_first.first
    
    block = EthBlock.order(imported_at: :desc).first
    
    block_number = block&.block_number.to_i + 1
    transaction_index = existing&.transaction_index.to_i + 1
    
    blockhash = "0x" + SecureRandom.hex(32)
    
    EthBlock.create!(
      block_number: block_number,
      blockhash: blockhash,
      parent_blockhash: block&.blockhash || "0x" + SecureRandom.hex(32),
      timestamp: Time.zone.now.to_i,
      imported_at: Time.zone.now,
      processing_state: "complete",
      transaction_count: 0
    )
    
    payload = {
      op: "updateAdminAddress",
      data: "0x1230000000000000000000000000000000000001"
    }
    
    uri = %{#{mimetype};rule=esip6,#{payload.to_json}}
    tx_hash = "0x" + SecureRandom.hex(32)
    sha = Digest::SHA256.hexdigest(uri)
    
    ethscription_attrs = {
      "transaction_hash"=>tx_hash,
      "block_number"=> block_number,
      "block_blockhash"=> blockhash,
      "creator"=>from.downcase,
      block_timestamp: block_timestamp,
      "initial_owner"=>'0x0000000000000000000000000000000000000000',
      "transaction_index"=>transaction_index,
      "content_uri"=> uri,
      mimetype: mimetype
    }
    
    Ethscription.transaction do
      eth = Ethscription.create!(ethscription_attrs)
      SystemConfigVersion.create_from_ethscription!(eth)
    end
  end
  
  def self.set_initial_start_block
    block_timestamp = Time.current.to_i
    from = SystemConfigVersion.current_admin_address
    mimetype = SystemConfigVersion.system_mimetype

    existing = Ethscription.newest_first.first
    
    block = EthBlock.order(imported_at: :desc).first
    
    block_number = block&.block_number.to_i + 1
    transaction_index = existing&.transaction_index.to_i + 1
    
    blockhash = "0x" + SecureRandom.hex(32)
    
    EthBlock.create!(
      block_number: block_number,
      blockhash: blockhash,
      parent_blockhash: block&.blockhash || "0x" + SecureRandom.hex(32),
      timestamp: Time.zone.now.to_i,
      imported_at: Time.zone.now,
      processing_state: "complete",
      transaction_count: 0
    )
    
    payload = {
      op: "updateStartBlockNumber",
      data: block_number + 1
    }
    
    uri = %{#{mimetype};rule=esip6,#{payload.to_json}}
    tx_hash = "0x" + SecureRandom.hex(32)
    sha = Digest::SHA256.hexdigest(uri)
    
    ethscription_attrs = {
      "transaction_hash"=>tx_hash,
      "block_number"=> block_number,
      "block_blockhash"=> blockhash,
      "creator"=>from.downcase,
      block_timestamp: block_timestamp,
      "initial_owner"=>'0x0000000000000000000000000000000000000000',
      "transaction_index"=>transaction_index,
      "content_uri"=> uri,
      mimetype: mimetype
    }
    
    Ethscription.transaction do
      eth = Ethscription.create!(ethscription_attrs)
      SystemConfigVersion.create_from_ethscription!(eth)
    end
  end
  
  def self.set_initial_supported_contracts
    new_names = [
      "EtherBridge",
      "EthscriptionERC20Bridge",
      "GenerativeERC721",
      "OpenEditionERC721",
      "PublicMintERC20",
      "UniswapSetupZapV2",
      "UniswapV2Factory",
      "UniswapV2Pair",
      "UniswapV2Router",
      "UniswapV2RouterWithRewards",
    ]
    
    new_hashes = new_names.map do |name|
      item = RubidityTranspiler.transpile_and_get(name)
      item.init_code_hash
    end
    
    ContractTestHelper.update_supported_contracts(*new_hashes, replace: true)
  end
  
  def update_supported_contracts(*new_names)
    new_hashes = new_names.map do |name|
      item = RubidityTranspiler.transpile_and_get(name)
      item.init_code_hash
    end
    
    ContractTestHelper.update_supported_contracts(*new_hashes)
  end
  
  def failure_message(interaction)
    test_location = caller_locations.find { |location| location.path.include?('/spec/') }
    "\nCall error: #{interaction.error}\nTest failed at: #{test_location}"
  end
  
  def self.dep
    ContractTestHelper.set_initial_supported_contracts
    
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
  
  def self.transform_old_format_to_new(payload)
    payload = payload.stringify_keys
    
    if payload.key?("protocol")
      return {data: {
        "type" => payload.delete("protocol"),
        "args" => payload.delete("constructorArgs")
      }}
    elsif payload.key?("contract")
      to = payload.delete("contract")
      data = {
        "function" => payload.delete("functionName"),
        "args" => payload.delete("args")
      }
      return { "to" => to, "data" => data }
    end
  
    payload
  end
  
  def self.update_supported_contracts(*new_hashes, replace: false)
    block_timestamp = Time.current.to_i
    from = SystemConfigVersion.current_admin_address
    mimetype = SystemConfigVersion.system_mimetype
    
    current_list = SystemConfigVersion.current.supported_contracts
    
    current_list = replace ? new_hashes : current_list + new_hashes
    
    payload = {
      op: "updateSupportedContracts",
      data: current_list.flatten
    }
    
    uri = %{#{mimetype};rule=esip6,#{payload.to_json}}
    
    tx_hash = "0x" + SecureRandom.hex(32)
    sha = Digest::SHA256.hexdigest(uri)
    
    existing = Ethscription.newest_first.first
    
    block = EthBlock.order(imported_at: :desc).first
    
    block_number = block&.block_number.to_i + 1
    transaction_index = existing&.transaction_index.to_i + 1
    
    blockhash = "0x" + SecureRandom.hex(32)
    
    EthBlock.create!(
      block_number: block_number,
      blockhash: blockhash,
      parent_blockhash: block&.blockhash || "0x" + SecureRandom.hex(32),
      timestamp: Time.zone.now.to_i,
      imported_at: Time.zone.now,
      processing_state: "complete",
      transaction_count: 0
    )
    
    ethscription_attrs = {
      "transaction_hash"=>tx_hash,
      "block_number"=> block_number,
      "block_blockhash"=> blockhash,
      "creator"=>from.downcase,
      block_timestamp: block_timestamp,
      "initial_owner"=>'0x0000000000000000000000000000000000000000',
      "transaction_index"=>transaction_index,
      "content_uri"=> uri,
      mimetype: mimetype
    }
    
    Ethscription.transaction do
      eth = Ethscription.create!(ethscription_attrs)
      SystemConfigVersion.create_from_ethscription!(eth)
    end
  end
  
  def self.trigger_contract_interaction(
    command: nil,
    from:,
    data: nil,
    payload: nil,
    block_timestamp: Time.current.to_i
  )
    payload = transform_old_format_to_new(data || payload).with_indifferent_access
    
    if payload['data'] && payload['data']['type']
      item = RubidityTranspiler.transpile_and_get(payload['data'].delete('type'))
      
      payload['data']['source_code'] = item.source_code
      payload['data']['init_code_hash'] = item.init_code_hash
    end
    
    if !payload['op']
      if payload['to']
        payload = { 'op' => 'call' }.merge(payload)
        payload['data'] = { 'to' => payload.delete('to') }.merge(payload['data'])
      else
        payload.delete('to')
        payload = { 'op' => 'create' }.merge(payload)
      end
    end
    
    mimetype = ContractTransaction.transaction_mimetype
    uri = %{#{mimetype},#{payload.to_json}}
    
    tx_hash = "0x" + SecureRandom.hex(32)
    sha = Digest::SHA256.hexdigest(uri)
    
    existing = Ethscription.newest_first.first
    
    block = EthBlock.order(imported_at: :desc).first
    
    block_number = block&.block_number.to_i + 1
    transaction_index = existing&.transaction_index.to_i + 1
    
    blockhash = "0x" + SecureRandom.hex(32)
    
    EthBlock.create!(
      block_number: block_number,
      blockhash: blockhash,
      parent_blockhash: block&.blockhash || "0x" + SecureRandom.hex(32),
      timestamp: Time.zone.now.to_i,
      imported_at: Time.zone.now,
      processing_state: "complete",
      transaction_count: 1
    )
    
    ethscription_attrs = {
      "transaction_hash"=>tx_hash,
      "block_number"=> block_number,
      "block_blockhash"=> blockhash,
      "creator"=>from.downcase,
      block_timestamp: block_timestamp,
      "initial_owner"=>'0x0000000000000000000000000000000000000000',
      "transaction_index"=>transaction_index,
      "content_uri"=> uri,
      mimetype: mimetype
    }
    
    eth = Ethscription.create!(ethscription_attrs)
    ContractTransaction.create_from_ethscription!(eth)
    
    eth.transaction_receipt
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
        "contract": creation_receipt.address,
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
        "contract": creation_receipt.address,
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
        "contract": creation_receipt.address,
        "functionName": "approve",
        "args": {
          "spender": "0xF99812028817Da95f5CF95fB29a2a7EAbfBCC27E",
          "amount": "2"
        },
      }
    )
    
    return
    created_id = creation_receipt.address
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
$cth = ContractTestHelper