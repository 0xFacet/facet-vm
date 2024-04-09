class WalletsController < ApplicationController
  include TokenDataProcessor
  cache_actions_on_block

  def get_tokens
    owner = TypedVariable.validated_value(:address, params[:address])
    owner_quoted = ActiveRecord::Base.connection.quote(owner)

    scope = Contract.where("current_state->'balanceOf'->? IS NOT NULL", owner)
      .where("current_state->'name' IS NOT NULL")
      .where("current_state->'symbol' IS NOT NULL")
      .where("current_state->'decimals' IS NOT NULL")

    if params[:factory]
      factory = TypedVariable.validated_value(:address, params[:factory])
      scope = scope.where("current_state->>'factory' = ?", factory)
    end

    tokens = scope.limit(200)
      .pluck(
        :address,
        Arel.sql("current_state->'name'"),
        Arel.sql("current_state->'symbol'"),
        Arel.sql("current_state->'balanceOf'->#{owner_quoted}"),
        Arel.sql("current_state->'decimals'"),
        Arel.sql("current_state->'tokenSmartContract'"),
        Arel.sql("current_state->'factory'")
      )

    keys = [:contract_address, :name, :symbol, :balance, :decimals, :token_smart_contract, :factory]
    token_balances = tokens.map do |values|
      keys.zip(values).to_h
    end

    render json: {
      result: numbers_to_strings(token_balances)
    }
  rescue ContractErrors::VariableTypeError => e
    render json: { error: e.message }, status: 400
  end

  def get_token_allowances
    owner = TypedVariable.validated_value(:address, params[:address])
    owner_quoted = ActiveRecord::Base.connection.quote(owner)

    contracts = Contract.where("current_state->'allowance'->? IS NOT NULL", owner)
      .limit(200)
      .pluck(
        :address,
        Arel.sql("current_state->'allowance'->#{owner_quoted}")
      )

    allowances_data = contracts.map do |contract_address, allowances|
      {
        contract_address: contract_address,
        allowances: allowances.map { |spender, amount| { spender: spender, allowance: amount } }
      }
    end

    render json: {
      result: numbers_to_strings(allowances_data)
    }
  rescue ContractErrors::VariableTypeError => e
    render json: { error: e.message }, status: 400
  end

  def get_nft_balances
    owner = TypedVariable.validated_value(:address, params[:address])
    owner_quoted = ActiveRecord::Base.connection.quote(owner)

    tokens = Contract.where("current_state->'_balanceOf'->? IS NOT NULL", owner)
      .where("current_state->'name' IS NOT NULL")
      .where("current_state->'symbol' IS NOT NULL")
      .where("current_state->'getApproved' IS NOT NULL")
      .where("current_state->'isApprovedForAll' IS NOT NULL")
      .limit(200)
      .pluck(
        :address,
        Arel.sql("current_state->'name'"),
        Arel.sql("current_state->'symbol'"),
        Arel.sql("current_state->'_balanceOf'->#{owner_quoted}")
      )

    keys = [:contract_address, :name, :symbol, :balance]
    token_balances = tokens.map do |values|
      keys.zip(values).to_h
    end

    render json: {
      result: numbers_to_strings(token_balances)
    }
  rescue ContractErrors::VariableTypeError => e
    render json: { error: e.message }, status: 400
  end

  def get_nft_approvals
    owner = TypedVariable.validated_value(:address, params[:address])
    owner_quoted = ActiveRecord::Base.connection.quote(owner)

    contracts = Contract.where("current_state->'isApprovedForAll'->? IS NOT NULL", owner)
      .limit(200)
      .pluck(
        :address,
        Arel.sql("current_state->'isApprovedForAll'->#{owner_quoted}")
      )

    approvals_data = contracts.map do |contract_address, approvals|
      {
        contract_address: contract_address,
        approvals: approvals.map { |approved_address, _| approved_address }
      }
    end

    render json: {
      result: approvals_data
    }
  rescue ContractErrors::VariableTypeError => e
    render json: { error: e.message }, status: 400
  end

  def pnl
    contract_address = params[:token_address]&.downcase
    paired_token_address = params[:paired_token_address]&.downcase
    router_address = params[:router_address]&.downcase
    factory_address = params[:factory_address]&.downcase
    from_address = params[:address]&.downcase
    from_timestamp = params[:from_timestamp].to_i
    to_timestamp = params[:to_timestamp]&.to_i
    max_processed_block_timestamp = EthBlock.processed.maximum(:timestamp).to_i

    to_timestamp = to_timestamp.present? ? [to_timestamp, max_processed_block_timestamp].min : max_processed_block_timestamp

    if factory_address&.match?(/\A0x[0-9a-f]{40}\z/)
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
      "wallets_pnl",
      contract_address,
      router_addresses,
      from_timestamp,
      to_timestamp,
      from_address
    ]

    cache_key << max_processed_block_timestamp if max_processed_block_timestamp - to_timestamp < 1.hour

    set_cache_control_headers(etag: cache_key, max_age: 12.seconds) do
      result = Rails.cache.fetch(cache_key) do
        swap_transactions = self.class.process_swaps(
          contract_address: contract_address,
          paired_token_address: paired_token_address,
          router_addresses: router_addresses,
          from_address: from_address,
          from_timestamp: from_timestamp,
          to_timestamp: to_timestamp
        )
        pnl = calculate_pnl(swap_transactions)
        numbers_to_strings(pnl)
      end


      render json: {
        result: result
      }
    end
  end

  private

  def calculate_pnl(swaps)
    total_revenue = 0
    total_cost = 0
    total_profit = 0
    buys = 0
    sells = 0

    swaps.each do |swap|
      if swap[:swap_type] == 'buy'
        buys += 1
        total_cost += swap[:paired_token_amount]
      elsif swap[:swap_type] == 'sell'
        sells += 1
        total_revenue += swap[:paired_token_amount]
      end
    end

    total_profit = total_revenue - total_cost

    {
      buys: buys,
      sells: sells,
      total_profit: total_profit,
      elapsed_time: swaps.any? ? swaps.last[:timestamp] - swaps.first[:timestamp] : 0
    }
  end
end
