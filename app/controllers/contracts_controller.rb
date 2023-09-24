class ContractsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 100).to_i
    per_page = 100 if per_page > 100

    contracts = Contract.all.order(created_at: :desc).page(page).per(per_page)

    render json: {
      result: convert_int_to_string(contracts)
    }
  end

  def all_abis
    render json: Contract.all_abis
  end

  def deployable_contracts
    render json: Contract.all_abis(deployable_only: true)
  end

  def show
    contract = Contract.find_by_address(params[:id])

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    render json: {
      result: convert_int_to_string(contract)
    }
  end

  def static_call
    args = JSON.parse(params.fetch(:args) { '{}' })
    env = JSON.parse(params.fetch(:env) { '{}' })

    begin
      result = ContractTransaction.make_static_call(
        contract: params[:address], 
        function_name: params[:function], 
        function_args: args,
        msgSender: env['msgSender']
      )
    rescue Contract::StaticCallError => e
      render json: {
        error: e.message
      }
      return
    end

    render json: {
      result: convert_int_to_string(result)
    }
  end

  def show_call_receipt
    receipt = ContractTransactionReceipt.includes(:contract_transaction).find_by_transaction_hash(params[:transaction_hash])

    if receipt.blank?
      render json: {
        error: "Call receipt not found"
      }
    else
      render json: {
        result: convert_int_to_string(receipt)
      }
    end
  end

  def contract_call_receipts
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 25).to_i
    per_page = 25 if per_page > 25

    contract = Contract.find_by_address(params[:address])
    receipts = contract.contract_transaction_receipts.includes(:contract_transaction).order(created_at: :desc).page(page).per(per_page)

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    render json: {
      result: convert_int_to_string(receipts)
    }
  end
  
  def simulate_transaction
    from = params[:from]
    tx_payload = JSON.parse(params[:tx_payload])
  
    begin
      receipt = ContractTransaction.simulate_transaction(
        from: from, tx_payload: tx_payload
      )
    rescue => e
      render json: { error: e.message }, status: 500
      return
    end
  
    render json: { result: convert_int_to_string(receipt) }
  end
  
  def pairs_with_tokens
    pair_ary = make_static_call(
      contract: params[:factory],
      function_name: "getAllPairs"
    )
  
    token_address = params[:token_address]
    user_address = params[:user_address]

    pairs = pair_ary.each_with_object({}) do |pair, hash|
      token_info0 = token_info(pair, "token0", user_address)
      token_info1 = token_info(pair, "token1", user_address)
  
      if token_address.nil? || token_info0[:address] == token_address || token_info1[:address] == token_address
        hash[pair] = {
          token0: token_info0,
          token1: token_info1
        }
      end
    end
  
    render json: { result: convert_int_to_string(pairs) }
  end
  
  private
  
  def token_info(pair, token_function, user_address)
    token_addr = make_static_call(
      contract: pair,
      function_name: token_function
    )
  
    token_info = {
      address: token_addr,
      name: make_static_call(
        contract: token_addr,
        function_name: "name"
      ),
      symbol: make_static_call(
        contract: token_addr,
        function_name: "symbol"
      )
    }
  
    if user_address.present?
      token_info[:userBalance] = make_static_call(
        contract: token_addr,
        function_name: "balanceOf",
        function_args: user_address
      )
    end
  
    token_info
  end
  
  def make_static_call(**kwargs)
    ContractTransaction.make_static_call(**kwargs)
  end
  
  def convert_int_to_string(result)
    result = result.as_json
  
    case result
    when Numeric
      result.to_s
    when Hash
      result.deep_transform_values { |value| convert_int_to_string(value) }
    when Array
      result.map { |value| convert_int_to_string(value) }
    else
      result
    end
  end
end
