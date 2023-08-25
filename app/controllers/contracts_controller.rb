class ContractsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 100).to_i
    per_page = 100 if per_page > 100

    contracts = Contract.all.order(created_at: :desc).page(page).per(per_page)

    json = Rails.cache.fetch(contracts) do
      contracts.to_a.as_json
    end

    render json: {
      result: contracts
    }
  end

  def all_abis
    render json: Contract.all_abis
  end

  def show
    contract = Contract.find_by_contract_id(params[:id])

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    json = Rails.cache.fetch(contract) do
      contract.as_json
    end

    render json: {
      result: contract
    }
  end

  def static_call
    args = JSON.parse(params.fetch(:args) { '{}' })
    env = JSON.parse(params.fetch(:env) { '{}' })

    contract = Contract.find_by_contract_id(params[:contract_id])

    if contract.blank?
      render json: { error: "Contract not found" }, status: 404
      return
    end

    begin
      result = contract.static_call(
        function_name: params[:function_name],
        args: args,
        msgSender: env['msgSender']
      )
    rescue Contract::StaticCallError => e
      render json: {
        error: e.message
      }
      return
    end

    render json: {
      result: result
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
        result: receipt
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
      result: receipts
    }
  end
end
