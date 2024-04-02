class WalletsController < ApplicationController
  cache_actions_on_block

  def get_token_balances
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
end
