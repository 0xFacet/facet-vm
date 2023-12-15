class TokensController < ApplicationController
  def historical_token_state
    as_of_block = params[:as_of_block].to_i
    contract_address = params[:address].to_s.downcase
    
    contract_state = ContractState.where(
      contract_address: contract_address,
    ).where("block_number <= ?", as_of_block).newest_first.first
    
    state = contract_state.state
    
    if !state["withdrawalIdAmount"]
      render json: { error: "Invalid contract" }, status: 400
      return
    end
    
    pending_withdraw_amount = convert_int_to_string(state['withdrawalIdAmount'].values.sum)
    
    render json: {
      result: {
        pending_withdraw_amount: pending_withdraw_amount,
        total_supply: convert_int_to_string(state['totalSupply']),
        trusted_smart_contract: state['trustedSmartContract'],
      }
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
      render json: { error: "Block not processed" }, status: 400
      return
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
        
        {
          txn_hash: receipt.transaction_hash,
          swapper_address: receipt.from_address,
          timestamp: receipt.block_timestamp,
          token_amount: token_log['data']['amount'],
          paired_token_amount: paired_token_log['data']['amount']
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