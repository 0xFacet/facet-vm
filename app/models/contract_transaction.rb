class ContractTransaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  include ContractErrors
  
  belongs_to :ethscription, primary_key: :ethscription_id, foreign_key: :transaction_hash
  has_one :contract_transaction_receipt, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_states, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_calls, foreign_key: :transaction_hash, primary_key: :transaction_hash, inverse_of: :contract_transaction
  has_many :contracts, foreign_key: :transaction_hash, primary_key: :transaction_hash
  belongs_to :contract, primary_key: 'address', foreign_key: 'to_contract_address', optional: true

  after_create :create_transaction_receipt!
  
  attr_accessor :tx_origin, :initial_call_info, :payload
  
  def self.required_mimetype
    "application/vnd.esc"
  end
  
  def self.on_ethscription_created(ethscription)
    begin
      new_from_ethscription(ethscription).execute_transaction
    rescue InvalidEthscriptionError => e
      Rails.logger.info(e.message)
    end
  end
  
  def self.new_from_ethscription(ethscription)
    new.tap do |r|
      r.import_ethscription(ethscription)
    end
  end
  
  def import_ethscription(ethscription)
    self.ethscription = ethscription

    begin
      self.payload = JSON.parse(ethscription.content)
      data = payload['data']
    rescue JSON::ParserError => e
      raise InvalidEthscriptionError.new(
        "JSON parse error: #{e.message}"
      )
    end
    
    validate_mimetype_and_to!
    
    assign_attributes(
      block_blockhash: ethscription.block_blockhash,
      block_timestamp: ethscription.creation_timestamp.to_i,
      block_number: ethscription.block_number,
      transaction_index: ethscription.transaction_index,
      tx_origin: ethscription.creator,
      
      initial_call_info: {
        to_contract_type: data['type'],
        to_contract_address: payload['to']&.downcase,
        function: data['function'],
        args: data['args'],
        type: (payload['to'].nil? ? :create : :call),
      }
    )
  end
  
  def initial_call
    contract_calls.sort_by(&:internal_transaction_index).first
  end
  
  def create_transaction_receipt!
    ContractTransactionReceipt.create!(
      transaction_hash: transaction_hash,
      caller: initial_call.from_address,
      timestamp: Time.zone.at(block_timestamp),
      function_name: initial_call.function,
      function_args: initial_call.args,
      logs: contract_calls.order(:internal_transaction_index).map(&:logs).flatten,
      status: status,
      contract_address: initial_call.effective_contract_address,
      error_message: initial_call.error
    )
  end
  
  def self.simulate_transaction(from:, tx_payload:)
    cache_key = [:simulate_transaction, ContractState.all, from, tx_payload]
  
    Rails.cache.fetch(cache_key) do
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
  end
  
  def self.make_static_call(contract:, function_name:, function_args: {}, msgSender: nil)
    cache_key = [:make_static_call, ContractState.all, contract, function_name, function_args, msgSender]
    
    Rails.cache.fetch(cache_key) do
      record = new(
        tx_origin: msgSender,
        initial_call_info: {
          type: :static_call,
          function: function_name,
          args: function_args,
          to_contract_address: contract,
        }
      )
  
      record.with_global_context do
        begin
          record.make_initial_call.as_json
        rescue ContractError, CallingNonExistentContractError => e
          raise StaticCallError.new("Static Call error #{e.message}")
        end
      end
    end
  end
  
  def with_global_context
    TransactionContext.set(
      call_stack: CallStack.new,
      current_transaction: self,
      tx_origin: tx_origin,
      block_number: block_number,
      block_timestamp: block_timestamp,
      block_blockhash: block_blockhash,
      transaction_hash: transaction_hash,
      transaction_index: transaction_index,
      ethscription: ethscription
    ) do
      yield
    end
  end
  
  def make_initial_call
    with_global_context do
      TransactionContext.call_stack.execute_in_new_frame(
        **initial_call_info
      )
    end
  end
  
  def execute_transaction
    begin
      make_initial_call
    rescue ContractError, TransactionError => e
      # puts e.message
    end
    
    save! unless is_static_call?
  end
  
  def is_static_call?
    initial_call.is_static_call?
  end
  
  def status
    contract_calls.any?(&:failure?) ? :error : :success
  end
  
  private
  
  def validate_mimetype_and_to!
    unless ethscription.initial_owner == ("0x" + "0" * 40) && ethscription.mimetype == ContractTransaction.required_mimetype
      raise InvalidEthscriptionError.new(
        "#{ethscription.inspect} does not trigger contract interaction"
      )
    end
    
    if payload['to'] && !payload['to'].to_s.match(/\A0x[a-f0-9]{40}\z/i)
      raise InvalidEthscriptionError.new(
        "#{ethscription.inspect} does not trigger contract interaction"
      )
    end
  end
end
