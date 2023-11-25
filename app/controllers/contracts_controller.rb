class ContractsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    scope = Contract.
      order(created_at: :desc).
      where.not(current_init_code_hash: nil).
      includes(:transaction_receipt)
    
    if params[:base_type]
      scope = scope.where(
        current_type: Contract.types_that_implement(params[:base_type]).map(&:name)
      )
    end
    
    if params[:init_code_hash]
      scope = scope.where(current_init_code_hash: params[:init_code_hash])
    end
    
    cache_key = ["contracts_index", scope, page, per_page]
  
    result = Rails.cache.fetch(cache_key) do
      contracts = scope.page(page).per(per_page).to_a
      convert_int_to_string(contracts)
    end
  
    render json: {
      result: result,
      count: scope.count
    }
  end

  def supported_contract_artifacts
    render json: {
      result: SystemConfigVersion.current_supported_contract_artifacts
    }
  end
  
  def all_abis
    render json: {
      result: Contract.all_abis
    }
  end

  def deployable_contracts
    render json: {
      result: Contract.all_abis(deployable_only: true)
    }
  end

  def show
    contract = Contract.find_by_address(params[:id])

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    render json: {
      result: convert_int_to_string(contract.as_json(include_current_state: true))
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
    receipt = TransactionReceipt.includes(:contract_transaction).find_by_transaction_hash(params[:transaction_hash])

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
    receipts = contract.transaction_receipts.includes(:contract_transaction).
      newest_first.page(page).per(per_page)

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    render json: {
      result: convert_int_to_string(receipts),
      count: receipts.total_count
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
      # Airbrake.notify(e)
      render json: { error: e.message }, status: 500
      return
    end
  
    render json: { result: convert_int_to_string(receipt) }
  end
  
  def pairs_with_tokens
    router = params[:router]
    token_address = params[:token_address]
    user_address = params[:user_address]
  
    cache_key = [:pairs_with_tokens, ContractState.all, router, token_address, user_address]
  
    pairs = Rails.cache.fetch(cache_key) do
      factory = make_static_call(
        contract: router,
        function_name: "factory"
      )
  
      pair_ary = make_static_call(
        contract: factory,
        function_name: "getAllPairs"
      )
  
      # Load pair_ary into memory
      contracts = Contract.where(address: pair_ary)
  
      # Fetch all token contracts in bulk
      token_addresses = contracts.map do |contract|
        [
          contract.fresh_implementation_with_current_state.token0,
          contract.fresh_implementation_with_current_state.token1
        ]
      end.flatten
      
      token_contracts = Contract.where(address: token_addresses.map(&:value)).index_by(&:address)
  
      result = contracts.each_with_object({}) do |contract, hash|
        ["token0", "token1"].each do |token_function|
          token_addr = contract.fresh_implementation_with_current_state.public_send(token_function)
          contract_implementation = token_contracts[token_addr.value].fresh_implementation_with_current_state
  
          token_info = {
            address: token_addr,
            name: contract_implementation.name,
            symbol: contract_implementation.symbol
          }
  
          if user_address.present?
            token_info[:userBalance] = contract_implementation.balanceOf(user_address)
            token_info[:allowance] = contract_implementation.allowance(user_address, router)
          end
  
          hash[contract.address] ||= {}
          hash[contract.address][token_function] = token_info
        end
      end
      
      convert_int_to_string(result)
    end
  
    render json: { result: pairs }
  rescue Contract::StaticCallError => e
    render json: {
      error: e.message
    }
  end
  
  def make_static_call(**kwargs)
    ContractTransaction.make_static_call(**kwargs)
  end
end
