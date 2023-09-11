class ContractTransaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  include ContractErrors
  
  belongs_to :ethscription, primary_key: :ethscription_id, foreign_key: :transaction_hash
  has_one :contract_transaction_receipt, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_states, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :internal_transactions, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contracts, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_one :created_contract, class_name: 'Contract', primary_key: 'created_contract_address', foreign_key: 'address'
  belongs_to :contract, primary_key: 'address', foreign_key: 'to_contract_address', optional: true

  after_create :create_transaction_receipt!
  
  def self.required_mimetype
    "application/vnd.esc"
  end
  
  def self.on_ethscription_created(ethscription)
    begin
      new_from_ethscription(ethscription).execute_transaction
    rescue EthscriptionDoesNotTriggerContractInteractionError => e
      Rails.logger.info(e.message)
    end
  end
  
  def self.new_from_ethscription(ethscription)
    new.tap do |r|
      r.import_ethscription = ethscription
    end
  end
  
  def import_ethscription=(ethscription)
    self.ethscription = ethscription

    validate_mimetype_and_to!
    
    begin
      payload = JSON.parse(ethscription.content)
      data = payload['data']
    rescue JSON::ParserError => e
      raise EthscriptionDoesNotTriggerContractInteractionError.new(
        "JSON parse error: #{e.message}"
      )
    end
    
    assign_attributes(
      block_blockhash: ethscription.block_blockhash,
      block_timestamp: ethscription.creation_timestamp.to_i,
      block_number: ethscription.block_number,
      transaction_index: ethscription.transaction_index,
      from_address: ethscription.creator,
      type: (payload['to'].nil? ? :create : :call),
      function: data['function'],
      args: data['args'],
      to_contract_type: data['type'],
      to_contract_address: payload['to'],
    )
  end
  
  def create_transaction_receipt!
    ContractTransactionReceipt.create!(
      transaction_hash: transaction_hash,
      caller: from_address,
      timestamp: Time.zone.at(block_timestamp),
      function_name: function,
      function_args: args,
      logs: logs,
      status: status,
      contract_address: to_contract_address,
      error_message: error.blank? ? "" : error.to_json
    )
  end
  
  def self.simulate_transaction(
    from:,
    tx_payload:
  )
    mimetype = ContractTransaction.required_mimetype
    uri = %{#{mimetype},#{tx_payload.to_json}}
  
    ethscription_attrs = {
      ethscription_id: "0x" + SecureRandom.hex(32),
      block_number: 1e15.to_i,
      block_blockhash: "0x" + SecureRandom.hex(32),
      current_owner: from.downcase,
      creator: from.downcase,
      creation_timestamp: Time.zone.now,
      initial_owner: "0x" + "0" * 40,
      transaction_index: 0,
      content_uri: uri,
      content_sha: Digest::SHA256.hexdigest(uri),
      mimetype: mimetype,
      mock_for_simulate_transaction: true
    }
    
    transaction_receipt = nil
  
    ActiveRecord::Base.transaction do
      eth = Ethscription.create!(ethscription_attrs)
      transaction_receipt = eth.contract_transaction.contract_transaction_receipt
  
      raise ActiveRecord::Rollback
    end
  
    transaction_receipt
  end
  
  def type
    super.to_sym
  end
  
  def self.make_static_call(contract:, function_name:, function_args: {}, msgSender: nil)
    record = new(
      type: :static_call,
      function: function_name,
      args: function_args,
      to_contract_address: contract,
      from_address: msgSender
    )
    
    record.with_global_context do
      begin
        record.initial_call.as_json
      rescue ContractError => e
        raise StaticCallError.new("Static Call error #{e.message}")
      end
    end
  end
  
  def with_global_context
    TransactionContext.set(
      current_transaction: self,
      tx_origin: from_address,
      block_number: block_number,
      block_timestamp: block_timestamp,
      block_blockhash: block_blockhash,
      transaction_hash: transaction_hash,
      transaction_index: transaction_index,
      ethscription: ethscription,
      log_event: method(:log_event)
    ) do
      yield
    end
  end
  
  def initial_call
    TransactionContext.call_stack.execute_in_new_frame(
      to_contract_address: to_contract_address,
      to_contract_type: to_contract_type,
      function_name: function,
      function_args: args,
      type: type
    )
  end

  def execute_transaction
    with_global_context do
      begin
        ActiveRecord::Base.transaction(requires_new: true) do
          initial_call.tap do |return_value|
            update!(
              return_value: return_value,
              status: :success
            )
          end
        end
      rescue ContractError, TransactionError => e
        update!(
          error: e.message,
          status: :error
        )
      end
    end
  end
  
  def is_create?
    type.to_sym == :create
  end
  
  def log_event(event)
    logs << event
    event
  end
  
  private
  
  def validate_mimetype_and_to!
    unless ethscription.initial_owner == ("0x" + "0" * 40) && ethscription.mimetype == ContractTransaction.required_mimetype
      raise EthscriptionDoesNotTriggerContractInteractionError.new(
        "#{ethscription.inspect} does not trigger contract interaction"
      )
    end
  end
end
