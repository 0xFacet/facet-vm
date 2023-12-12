class TokensController < ApplicationController
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
    max_processed_block_timestamp = EthBlock.processed.maximum(:block_timestamp).to_i
  
    if max_processed_block_timestamp < to_timestamp
      render json: { error: "Block not processed" }, status: 400
      return
    end
  
    if from_timestamp > to_timestamp || to_timestamp - from_timestamp > 1.month
      render json: { error: "Invalid timestamp range" }, status: 400
      return
    end
  
    cache_key = [
      "token_swaps",
      contract_address,
      from_timestamp,
      to_timestamp
    ]
  
    cache_key << max_processed_block_timestamp if max_processed_block_timestamp - to_timestamp < 1.hour
  
    result = Rails.cache.fetch(cache_key) do
      transactions = TransactionReceipt.where(status: 'success', function: ['swapExactTokensForTokens', 'swapTokensForExactTokens'])
        .where('block_timestamp >= ? AND block_timestamp <= ?', from_timestamp, to_timestamp)
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
  
      convert_int_to_string(transactions)
    end
  
    render json: {
      result: result
    }
  end

  def volume
    contract_address = params[:address]&.downcase
    one_day_ago = 24.hours.ago.to_i

    cache_key = ["token_volume", contract_address, Time.current.hour]

    result = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      total_volume = calculate_volume(contract_address)
      last_24_hours_volume = calculate_volume(contract_address, one_day_ago)

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

  def calculate_volume(contract_address, start_time = nil)
    query = TransactionReceipt.where(status: 'success', function: ['swapExactTokensForTokens', 'swapTokensForExactTokens'])
      .where("EXISTS (
        SELECT 1
        FROM jsonb_array_elements(logs) AS log
        WHERE (log ->> 'contractAddress') = ?
        AND (log ->> 'event') = 'Transfer'
      )", contract_address)
    query = query.where('block_timestamp >= ?', start_time.to_i) if start_time

    query.pluck(:logs)
      .flatten
      .select { |log| log['contractAddress'] == "0x1673540243e793b0e77c038d4a88448eff524dce" }
      .sum { |log| log['data']['amount'].to_i }
  end
end