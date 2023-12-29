class TokensController < ApplicationController
  def get_allowance
    address = TypedVariable.validated_value(:address, params[:address])
    owner = TypedVariable.validated_value(:address, params[:owner])
    spender = TypedVariable.validated_value(:address, params[:spender])
    
    owner_address = ActiveRecord::Base.connection.quote(owner)
    spender_address = ActiveRecord::Base.connection.quote(spender)
    
    render_with_caching(
      [EthBlock.max_processed_block_hash, address, owner, spender],
      max_age: 1.second,
    ) do
      allowance = Contract.where(address: address)
                  .pluck(Arel.sql("current_state->'allowance'->#{owner_address}->>#{spender_address}"))
                  .first.to_i
                          
      { result: allowance.to_s }
    end
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
      result: convert_int_to_string(result)
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

      if !state["balanceOf"]
        render json: { error: "Invalid contract" }, status: 400
        return
      end

      convert_int_to_string(state["balanceOf"])
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
      
      convert_int_to_string(cooked_transactions)
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

    result = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      total_volume = calculate_volume(contract_address: contract_address, volume_contract: volume_contract)
      last_24_hours_volume = calculate_volume(contract_address: contract_address, volume_contract: volume_contract, start_time: one_day_ago)

      convert_int_to_string({
        total_volume: total_volume,
        last_24_hours_volume: last_24_hours_volume
      })
    end

    render json: {
      result: result
    }
  end

  private

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