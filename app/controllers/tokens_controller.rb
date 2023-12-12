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
    max_processed_block_number = EthBlock.max_processed_block_number
  
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
  
    cache_key << max_processed_block_number if max_processed_block_timestamp - to_timestamp < 1.hour
  
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
end