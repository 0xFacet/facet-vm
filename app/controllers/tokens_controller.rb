class TokensController < ApplicationController
  cache_actions_on_block

  def tokens_owned_by_address
    address = TypedVariable.validated_value(:address, params[:address])

    cache_key = [
      "tokens_owned_by_address",
      address,
      EthBlock.max_processed_block_number
    ]

    result = Rails.cache.fetch(cache_key) do
      tokens = Contract.where("current_state->'balanceOf'->>? > '0'", address)
        .pluck(
          :address,
          Arel.sql("current_state->'name'"),
          Arel.sql("current_state->'symbol'"),
          Arel.sql("current_state->'balanceOf'->>#{ActiveRecord::Base.connection.quote(address)}"),
          Arel.sql("current_state->'decimals'")
        )

      token_balances = tokens.map do |address, name, symbol, balance, decimals|
        { address: address, name: name, symbol: symbol, balance: balance, decimals: decimals }
      end
      numbers_to_strings(token_balances)
    end

    render json: {
      result: result
    }
  end

  def get_allowance
    address = TypedVariable.validated_value(:address, params[:address])
    owner = TypedVariable.validated_value(:address, params[:owner])
    spender = TypedVariable.validated_value(:address, params[:spender])
    
    owner_address = ActiveRecord::Base.connection.quote(owner)
    spender_address = ActiveRecord::Base.connection.quote(spender)

    allowance = Contract.where(address: address)
                .pluck(Arel.sql("current_state->'allowance'->#{owner_address}->>#{spender_address}"))
                .first.to_i
                        
    render json: {
      result: allowance.to_s
    }
  rescue ContractErrors::VariableTypeError => e
    render json: { error: e.message }, status: 400
  end
  
  def historical_token_state
    as_of_block = params[:as_of_block].to_i
    contract_address = params[:address].to_s.downcase
    
    contract_state_future = ContractState.where(
      contract_address: contract_address,
    ).where("block_number <= ?", as_of_block).newest_first.limit(1).load_async
    
    function_event_pairs = [
      ['bridgeIn', 'BridgedIn'],
      ['markWithdrawalComplete', 'WithdrawalComplete']
    ]
    
    async_result = calculate_total_amounts_async(
      function_event_pairs: function_event_pairs,
      contract_address: contract_address,
      as_of_block: as_of_block
    )
    
    contract_state = contract_state_future.first
    
    state = contract_state.state
    
    if !state["withdrawalIdAmount"]
      render json: { error: "Invalid contract" }, status: 400
      return
    end
    
    pending_withdraw_amount = state['withdrawalIdAmount'].values.sum
    
    result = async_result.first
    
    total_bridged_in = result.bridgein_sum.to_i
    total_withdraw_complete = result.markwithdrawalcomplete_sum.to_i
    
    result = {
      as_of_block: as_of_block,
      contract_address: contract_address,
      pending_withdraw_amount: pending_withdraw_amount,
      total_supply: state['totalSupply'],
      trusted_smart_contract: state['trustedSmartContract'],
      total_bridged_in: total_bridged_in,
      total_withdraw_complete: total_withdraw_complete
    }
    
    render json: {
      result: numbers_to_strings(result)
    }
  end
  
  def holders
    contract_address = params[:address]&.downcase

    cache_key = [
      "token_holders",
      contract_address,
      EthBlock.max_processed_block_number
    ]

    result = Rails.cache.fetch(cache_key) do
      contract = Contract.find_by(deployed_successfully: true, address: contract_address)
      
      if contract.blank?
        render json: { error: "Contract not found" }, status: 404
        return
      end

      state = contract.current_state

      holderBalances = state["balanceOf"] || state["_balanceOf"]

      if !holderBalances
        render json: { error: "Invalid contract" }, status: 400
        return
      end

      numbers_to_strings(holderBalances)
    end

    render json: {
      result: result
    }
  end

  def swaps
    contract_address = params[:address]&.downcase
    from_timestamp = params[:from_timestamp].to_i
    to_timestamp = params[:to_timestamp].to_i
    router_address = params[:router_address]&.downcase
    max_processed_block_timestamp = EthBlock.processed.maximum(:timestamp).to_i
  
    if max_processed_block_timestamp < to_timestamp
      to_timestamp = max_processed_block_timestamp
    end
    
    unless router_address.to_s.match?(/\A0x[0-9a-f]{40}\z/)
      render json: { error: "Invalid router address" }, status: 400
      return
    end
    
    if from_timestamp > to_timestamp || to_timestamp - from_timestamp > 1.month
      render json: { error: "Invalid timestamp range" }, status: 400
      return
    end
  
    cache_key = [
      "token_swaps",
      contract_address,
      router_address,
      from_timestamp,
      to_timestamp
    ]
  
    cache_key << max_processed_block_timestamp if max_processed_block_timestamp - to_timestamp < 1.hour
  
    result = Rails.cache.fetch(cache_key) do
      transactions = TransactionReceipt.where(
        to_contract_address: router_address,
        status: "success",
        function: ["swapExactTokensForTokens", "swapTokensForExactTokens"]
      )
        .where("block_timestamp >= ? AND block_timestamp <= ?", from_timestamp, to_timestamp)
        .where("EXISTS (
          SELECT 1
          FROM jsonb_array_elements(logs) AS log
          WHERE (log ->> 'contractAddress') = ?
          AND (log ->> 'event') = 'Transfer'
        )", contract_address)

      if transactions.blank?
        render json: { error: "Transactions not found" }, status: 404
        return
      end
      
      cooked_transactions = transactions.map do |receipt|
        relevant_transfer_logs = receipt.logs.select do |log|
          log["event"] == "Transfer" && log["data"]["to"] != router_address
        end
        
        token_log = relevant_transfer_logs.detect do |log|
          log['contractAddress'] == contract_address
        end
        
        paired_token_log = (relevant_transfer_logs - [token_log]).first

        swap_type = if token_log['data']['to'] == receipt.from_address
          'buy'
        else
          'sell'
        end
        
        {
          txn_hash: receipt.transaction_hash,
          swapper_address: receipt.from_address,
          timestamp: receipt.block_timestamp,
          token_amount: token_log['data']['amount'],
          paired_token_amount: paired_token_log['data']['amount'],
          swap_type: swap_type,
          transaction_index: receipt.transaction_index,
          block_number: receipt.block_number
        }
      end
      
      numbers_to_strings(cooked_transactions)
    end
  
    render json: {
      result: result
    }
  end

  def volume
    volume_contract = params[:volume_contract]&.downcase
    contract_address = params[:address]&.downcase
    one_day_ago = 24.hours.ago.to_i

    cache_key = ["token_volume", contract_address, volume_contract]
    
    set_cache_control_headers(max_age: 12.seconds, s_max_age: 1.hour)

    result = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      total_volume = calculate_volume(contract_address: contract_address, volume_contract: volume_contract)
      last_24_hours_volume = calculate_volume(contract_address: contract_address, volume_contract: volume_contract, start_time: one_day_ago)

      numbers_to_strings({
        total_volume: total_volume,
        last_24_hours_volume: last_24_hours_volume
      })
    end

    render json: {
      result: result
    }
  end

  def token_prices
    token_addresses = params[:token_addresses].to_s.split(',')
    eth_contract_address = params[:eth_contract_address]
    router_address = params[:router_address]

    if token_addresses.length > 50
      render json: { error: "Too many token addresses, limit is 50" }, status: 400
      return
    end

    cache_key = [
      "token_prices",
      token_addresses.join(','),
      eth_contract_address,
      router_address,
      EthBlock.max_processed_block_number
    ]

    result = Rails.cache.fetch(cache_key) do
      prices = token_addresses.map do |address|
        last_swap_price_in_eth = get_last_swap_price_for_token(address, eth_contract_address, router_address)
        last_swap_price_in_wei = (last_swap_price_in_eth * 1e18).to_i
        { token_address: address, last_swap_price: last_swap_price_in_wei.to_s }
      end

      numbers_to_strings(prices)
    end

    render json: {
      result: result
    }
  end
  
  private
  
  def get_last_swap_price_for_token(token_address, eth_contract_address, router_address)
    token_address = token_address.downcase
    eth_contract_address = eth_contract_address.downcase
    router_address = router_address.downcase

    recent_transaction = TransactionReceipt.where(
      status: "success",
      function: ["swapExactTokensForTokens", "swapTokensForExactTokens"],
      to_contract_address: router_address
    )
    .where("EXISTS (
      SELECT 1
      FROM jsonb_array_elements(logs) AS log
      WHERE (log ->> 'contractAddress') = ?
      AND (log ->> 'event') = 'Transfer'
    )", token_address)
    .where("EXISTS (
      SELECT 1
      FROM jsonb_array_elements(logs) AS log
      WHERE (log ->> 'contractAddress') = ?
      AND (log ->> 'event') = 'Transfer'
    )", eth_contract_address)
    .newest_first
    .first

    return nil if recent_transaction.blank?

    process_transaction_for_swap_price(recent_transaction, token_address, eth_contract_address, router_address)
  end

  def process_transaction_for_swap_price(transaction, token_address, eth_contract_address, router_address)
    relevant_transfer_logs = transaction.logs.select do |log|
      log["event"] == "Transfer" && log["data"]["to"] != router_address
    end

    return nil if relevant_transfer_logs.empty?

    token_log = relevant_transfer_logs.find { |log| log['contractAddress'] == token_address }
    eth_log = relevant_transfer_logs.find { |log| log['contractAddress'] == eth_contract_address }

    return nil if token_log.nil? || eth_log.nil?

    token_amount = token_log['data']['amount'].to_i
    eth_amount = eth_log['data']['amount'].to_i

    swap_price = eth_amount.to_f / token_amount
    swap_price
  end

  def calculate_total_amounts_async(function_event_pairs:, contract_address:, as_of_block:)
    select_query_parts = function_event_pairs.map do |function, event|
      "SUM((CASE WHEN function = '#{function}' AND log->>'event' = '#{event}' THEN (log->'data'->>'amount')::numeric ELSE 0 END)) as #{function}_sum"
    end
  
    TransactionReceipt
      .joins("CROSS JOIN LATERAL jsonb_array_elements(logs) as log")
      .where("status = ? AND to_contract_address = ? AND block_number <= ?", 'success', contract_address, as_of_block)
      .select(Arel.sql(select_query_parts.join(", "))).load_async
  end
  
  def calculate_volume(contract_address:, volume_contract:, start_time: nil)
    query = TransactionReceipt.where(status: "success", function: ["swapExactTokensForTokens", "swapTokensForExactTokens"])
      .where("EXISTS (
        SELECT 1
        FROM jsonb_array_elements(logs) AS log
        WHERE (log ->> 'contractAddress') = ?
        AND (log ->> 'event') = 'Transfer'
      )", contract_address)
    query = query.where("block_timestamp >= ?", start_time.to_i) if start_time

    query.pluck(:logs)
      .flatten
      .sum do |log|
        next 0 unless log["contractAddress"] == volume_contract && log["event"] == "Transfer"
        log["data"]["amount"].to_i
      end
  end
end