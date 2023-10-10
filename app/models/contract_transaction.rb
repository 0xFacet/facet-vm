class ContractTransaction < ApplicationRecord
  self.inheritance_column = :_type_disabled

  include ContractErrors
  
  belongs_to :ethscription, primary_key: :ethscription_id, foreign_key: :transaction_hash, optional: true
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
  
  def self.create_from_ethscription!(ethscription)
    return unless ENV.fetch('ETHEREUM_NETWORK') == "eth-goerli" || Rails.env.development?
    
    ContractTransaction.transaction do
      new_from_ethscription(ethscription).execute_transaction
    
      end_time = Time.current
      
      ethscription.update_columns(
        contract_actions_processed_at: end_time,
        updated_at: end_time
      )
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
      Rails.logger.info "JSON parse error: #{e.message}"
      return
    end
    
    assign_attributes(
      block_blockhash: ethscription.block_blockhash,
      block_timestamp: ethscription.creation_timestamp,
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
  
      transaction_receipt = nil
  
      ActiveRecord::Base.transaction do
        if !EthBlock.exists?
          EthBlock.create!(
            block_number: 1,
            blockhash: "0x" + SecureRandom.hex(32),
            parent_blockhash: "0x" + SecureRandom.hex(32),
            timestamp: Time.zone.now.to_i,
            imported_at: Time.zone.now,
            processing_state: "complete"
          )
        end
        
        block_number = EthBlock.where(processing_state: :complete).
          order(imported_at: :desc).limit(1).pluck(:block_number).first
        
        ethscription_attrs = {
          ethscription_id: "0x" + SecureRandom.hex(32),
          block_number: block_number,
          block_blockhash: "0x" + SecureRandom.hex(32),
          current_owner: from.downcase,
          creator: from.downcase,
          creation_timestamp: Time.zone.now.to_i,
          initial_owner: "0x" + "0" * 40,
          transaction_index: Time.zone.now.to_i,
          content_uri: uri,
          content_sha: Digest::SHA256.hexdigest(uri),
          mimetype: mimetype,
          mock_for_simulate_transaction: true
        }
        
        eth = Ethscription.create!(ethscription_attrs)
        ContractTransaction.create_from_ethscription!(eth)
        transaction_receipt = eth.contract_transaction_receipt
        
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
    return unless mimetype_and_to_valid?
    
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
  
  def mimetype_and_to_valid?
    unless ethscription.initial_owner == ("0x" + "0" * 40) && ethscription.mimetype == ContractTransaction.required_mimetype
      Rails.logger.info("#{ethscription.inspect} does not trigger contract interaction")
      return false
    end
    
    if !payload || payload['to'] && !payload['to'].to_s.match(/\A0x[a-f0-9]{40}\z/i)
      Rails.logger.info("#{ethscription.inspect} does not trigger contract interaction")
      return false
    end
    
    true
  end
end
