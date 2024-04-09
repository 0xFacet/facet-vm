class TokensController < ApplicationController
  include TokenDataProcessor
  cache_actions_on_block

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
    paired_token_address = params[:paired_token_address]&.downcase
    router_address = params[:router_address]&.downcase
    factory_address = params[:factory_address]&.downcase
    from_address = params[:from_address]&.downcase
    from_timestamp = params[:from_timestamp].to_i
    to_timestamp = params[:to_timestamp]&.to_i
    max_processed_block_timestamp = EthBlock.processed.maximum(:timestamp).to_i

    to_timestamp = to_timestamp.present? ? [to_timestamp, max_processed_block_timestamp].min : max_processed_block_timestamp

    if router_address&.match?(/\A0x[0-9a-f]{40}\z/)
      router_addresses = [router_address]
    elsif factory_address&.match?(/\A0x[0-9a-f]{40}\z/)
      router_addresses = Contract.where("current_type LIKE ?", "FacetSwapV1Router%")
        .where("current_state->>'factory' = ?", factory_address)
        .pluck(:address)
    else
      render json: { error: "Invalid or missing router/factory address" }, status: 400
      return
    end

    if router_addresses.blank?
      render json: { error: "No routers found for given factory" }, status: 404
      return
    end

    if from_timestamp > to_timestamp || from_address.blank? && to_timestamp - from_timestamp > 1.month
      render json: { error: "Invalid timestamp range" }, status: 400
      return
    end
  
    cache_key = [
      "token_swaps",
      contract_address,
      router_addresses,
      from_timestamp,
      to_timestamp,
      from_address
    ]
  
    cache_key << max_processed_block_timestamp if max_processed_block_timestamp - to_timestamp < 1.hour

    set_cache_control_headers(etag: cache_key, max_age: 12.seconds) do
      result = Rails.cache.fetch(cache_key) do
        swap_transactions = process_swaps(
          contract_address: contract_address,
          paired_token_address: paired_token_address,
          router_addresses: router_addresses,
          from_address: from_address,
          from_timestamp: from_timestamp,
          to_timestamp: to_timestamp
        )
        numbers_to_strings(swap_transactions)
      end

      render json: {
        result: result
      }
    end
  end

  def volume
    volume_contract = params[:volume_contract]&.downcase
    contract_address = params[:address]&.downcase

    cache_key = ["token_volume", contract_address, volume_contract]

    set_cache_control_headers(max_age: 12.seconds, s_max_age: 5.minutes)

    result = Rails.cache.fetch(cache_key, expires_in: 5.minute) do
      time_ranges = {
        total_volume: nil,
        last_7_days_volume: 7.days.ago,
        last_24_hours_volume: 24.hours.ago,
        last_6_hours_volume: 6.hours.ago,
        last_1_hour_volume: 1.hour.ago,
        last_5_minutes_volume: 5.minutes.ago
      }

      calculate_volumes(contract_address: contract_address, volume_contract: volume_contract, time_ranges: time_ranges)
    end

    render json: {
      result: result
    }
  end

  def token_prices
    token_addresses = params[:token_addresses].to_s.split(',')
    eth_contract_address = params[:eth_contract_address]
    router_address = params[:router_address]
    factory_address = params[:factory_address]

    if router_address
      factory_address = Contract.where(address: router_address)
        .pluck(Arel.sql("current_state->'factory'"))
        .first
    end

    if token_addresses.length > 50
      render json: { error: "Too many token addresses, limit is 50" }, status: 400
      return
    end

    cache_key = [
      "token_prices",
      token_addresses.join(','),
      eth_contract_address,
      factory_address,
      EthBlock.max_processed_block_number
    ]

    result = Rails.cache.fetch(cache_key) do
      prices = token_addresses.map do |address|
        price = get_price_for_token(
          token_address: address,
          paired_token_address: eth_contract_address,
          factory_address: factory_address
        )
        { token_address: address, price: price }
      end

      numbers_to_strings(prices)
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

  def calculate_volumes(contract_address:, volume_contract:, time_ranges:)
    conditional_sums = time_ranges.map do |label, start_time|
      if start_time
        "SUM(CASE WHEN block_timestamp >= #{start_time.to_i} THEN (log -> 'data' ->> 'amount')::numeric ELSE 0 END) AS \"#{label}\""
      else
        "SUM((log -> 'data' ->> 'amount')::numeric) AS \"#{label}\""
      end
    end.join(", ")

    query = <<-SQL
      SELECT #{conditional_sums}
      FROM transaction_receipts,
           jsonb_array_elements(logs) AS log
      WHERE status = 'success'
        AND function IN ('swapExactTokensForTokens', 'swapTokensForExactTokens')
        AND (log ->> 'contractAddress') = :volume_contract
        AND (log ->> 'event') = 'Transfer'
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(logs) AS inner_log
          WHERE (inner_log ->> 'contractAddress') = :contract_address
            AND (inner_log ->> 'event') = 'Transfer'
        )
    SQL

    query_params = { contract_address: contract_address, volume_contract: volume_contract }

    result = TransactionReceipt.find_by_sql([query, query_params])

    formatted_result = result.first.as_json.transform_values do |value|
      value.to_i.to_s
    end

    formatted_result
  end
end