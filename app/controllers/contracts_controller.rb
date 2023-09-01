class ContractsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 100).to_i
    per_page = 100 if per_page > 100

    contracts = Contract.all.order(created_at: :desc).page(page).per(per_page)

    render json: {
      result: contracts.map do |i|
        i.as_json.deep_transform_values do |value|
          value.is_a?(Integer) ? value.to_s : value
        end
      end
    }
  end

  def all_abis
    render json: Contract.all_abis
  end

  def deployable_contracts
    render json: Contract.all_abis(deployable_only: true)
  end

  def show
    contract = Contract.find_by_contract_id(params[:id])

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    render json: {
      result: contract.as_json.deep_transform_values do |value|
        value.is_a?(Integer) ? value.to_s : value
      end
    }
  end

  def static_call
    args = JSON.parse(params.fetch(:args) { '{}' })
    env = JSON.parse(params.fetch(:env) { '{}' })

    begin
      result = ContractTransaction.make_static_call(
        contract_id: params[:contract_id], 
        function_name: params[:function_name], 
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
      result: result.is_a?(Integer) ? result.to_s : result
    }
  end

  def show_call_receipt
    receipt = ContractCallReceipt.find_by_ethscription_id(params[:ethscription_id])

    if receipt.blank?
      render json: {
        error: "Call receipt not found"
      }
    else
      render json: {
        result: receipt.as_json.deep_transform_values do |value|
          value.is_a?(Integer) ? value.to_s : value
        end
      }
    end
  end

  def contract_call_receipts
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 25).to_i
    per_page = 25 if per_page > 25

    contract = Contract.find_by_contract_id(params[:contract_id])
    receipts = contract.call_receipts.order(created_at: :desc).page(page).per(per_page)

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    render json: {
      result: receipts.map do |i|
        i.as_json.deep_transform_values do |value|
          value.is_a?(Integer) ? value.to_s : value
        end
      end
    }
  end
  
  def simulate_transaction
    command = params[:command]
    from = params[:from]
    data = JSON.parse(params[:data])
  
    begin
      receipt = ContractTransaction.simulate_transaction(command: command, from: from, data: data)
    rescue => e
      render json: { error: e.message }, status: 500
      return
    end
  
    render json: { result: receipt }
  end
end
