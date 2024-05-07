class WalletsController < ApplicationController
  include TokenDataProcessor
  cache_actions_on_block

  def get_tokens
    owner = TypedVariable.validated_value(:address, params[:address])
    owner_quoted = ActiveRecord::Base.connection.quote(owner)

    scope = Contract.where("(current_state->'balanceOf'->? IS NOT NULL OR current_state->'userWithdrawalId'->? IS NOT NULL)", owner, owner)
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
        Arel.sql("current_state->'userWithdrawalId'->#{owner_quoted}"),
        Arel.sql("current_state->'withdrawalIdAmount'->(current_state->'userWithdrawalId'->#{owner_quoted})"),
        Arel.sql("current_state->'decimals'"),
        Arel.sql("current_state->'tokenSmartContract'"),
        Arel.sql("current_state->'factory'")
      )

    keys = [:contract_address, :name, :symbol, :balance, :withdrawal_id, :withdrawal_amount, :decimals, :token_smart_contract, :factory]
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
    from_address = params[:address]&.downcase
    token_address = params[:token_address]&.downcase
    paired_token_address = params[:paired_token_address]&.downcase
    router_address = params[:router_address]&.downcase
    factory_address = params[:factory_address]&.downcase
    max_processed_block_timestamp = EthBlock.processed.maximum(:timestamp).to_i

    if !paired_token_address&.match?(/\A0x[0-9a-f]{40}\z/)
      render json: { error: "Invalid or missing paired token address" }, status: 404
      return
    end

    if factory_address&.match?(/\A0x[0-9a-f]{40}\z/)
      router_addresses = Contract.where("current_type LIKE ?", "FacetSwapV1Router%")
        .where("current_state->>'factory' = ?", factory_address)
        .pluck(:address)
    else
      render json: { error: "Invalid or missing factory address" }, status: 400
      return
    end

    if router_addresses.blank?
      render json: { error: "No routers found for given factory" }, status: 404
      return
    end

    cache_key = [
      "wallets_pnl",
      token_address,
      router_addresses,
      from_address,
      max_processed_block_timestamp
    ]

    set_cache_control_headers(etag: cache_key, max_age: 12.seconds) do
      result = Rails.cache.fetch(cache_key) do
        swap_transactions = process_swaps(
          contract_address: token_address,
          paired_token_address: paired_token_address,
          router_addresses: router_addresses,
          from_address: from_address,
          from_timestamp: 0,
          to_timestamp: max_processed_block_timestamp
        )
        balance = Contract.get_storage_value_by_path(
          token_address,
          [
            'balanceOf',
            from_address
          ]
        )
        decimals = Contract.get_storage_value_by_path(
          token_address,
          ['decimals']
        )
        price = get_price_for_token(
          token_address: token_address,
          paired_token_address: paired_token_address,
          factory_address: factory_address
        )
        pnl = calculate_pnl(swap_transactions, balance, decimals, price)
        numbers_to_strings(pnl)
      end

      render json: {
        result: result
      }
    end
  end

  private

  def calculate_pnl(swaps, balance, decimals, price)
    total_cost = 0
    total_revenue = 0
    realized_profit = 0
    buys = 0
    sells = 0
    total_bought = 0
    total_sold = 0
    percent_sold = 0

    current_market_value = ((balance.to_f / (10 ** decimals.to_i)) * price.to_i).to_i

    swaps.each do |swap|
      if swap[:swap_type] == 'buy'
        buys += 1
        total_cost += swap[:paired_token_amount]
        total_bought += swap[:token_amount]
      elsif swap[:swap_type] == 'sell'
        sells += 1
        total_revenue += swap[:paired_token_amount]
        total_sold += swap[:token_amount]
      end
    end

    if sells > 0
      percent_sold = total_sold.to_f / (total_sold + balance.to_i).to_f
      realized_profit = (total_revenue - (percent_sold * total_cost)).to_i
    end

    percent_not_sold = 1 - percent_sold
    unrealized_profit = (current_market_value - (percent_not_sold * total_cost)).to_i

    current_time = Time.now.to_i
    elapsed_time = swaps.any? ? current_time - swaps.first[:timestamp] : 0

    {
      buys: buys,
      sells: sells,
      total_cost: total_cost,
      total_revenue: total_revenue,
      total_bought: total_bought,
      total_sold: total_sold,
      realized_profit: realized_profit,
      percent_not_sold: percent_not_sold,
      percent_sold: percent_sold,
      unrealized_profit: unrealized_profit,
      current_market_value: current_market_value,
      total_profit: realized_profit + unrealized_profit,
      elapsed_time: elapsed_time
    }
  end
end
