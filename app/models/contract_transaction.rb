class ContractTransaction < ApplicationRecord
  include ContractErrors
  
  belongs_to :ethscription, primary_key: :transaction_hash, foreign_key: :transaction_hash, optional: true
  has_one :transaction_receipt, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_states, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_calls, foreign_key: :transaction_hash, primary_key: :transaction_hash, inverse_of: :contract_transaction
  has_many :contracts, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_artifacts, foreign_key: :transaction_hash, primary_key: :transaction_hash

  attr_accessor :tx_origin, :payload
  
  def self.transaction_mimetype
    "application/vnd.facet.tx+json"
  end
  
  def self.validate_start_block_passed!(ethscription)
    system_start_block = SystemConfigVersion.current.start_block_number
    valid = system_start_block && ethscription.block_number >= system_start_block
    
    unless valid
      raise InvalidEthscriptionError.new("Start block not passed")
    end
  end
  
  def self.create_from_ethscription!(ethscription, persist:)
    validate_start_block_passed!(ethscription)
    
    new(ethscription: ethscription).tap do |contract_tx|
      contract_tx.execute_transaction(persist: persist)      
    end
  end
  
  def ethscription=(ethscription)
    assign_attributes(
      block_blockhash: ethscription.block_blockhash,
      block_timestamp: ethscription.block_timestamp,
      block_number: ethscription.block_number,
      transaction_index: ethscription.transaction_index,
      tx_origin: ethscription.creator
    )
    
    begin
      self.payload = OpenStruct.new(JSON.parse(ethscription.content))
    rescue JSON::ParserError, NoMethodError => e
      raise InvalidEthscriptionError.new("JSON parse error: #{e.message}")
    end
    
    super(ethscription)
  end
  
  def validate_payload!
    unless payload.present? && payload.data&.is_a?(Hash)
      raise InvalidEthscriptionError.new("Payload not present")
    end
    
    op = payload.op&.to_sym
    data_keys = payload.data.keys.map(&:to_sym).to_set

    unless [:create, :call, :static_call].include?(op)
      raise InvalidEthscriptionError.new("Invalid op: #{op}")
    end
    
    if op == :create
      unless [
        [:init_code_hash].to_set,
        [:init_code_hash, :args].to_set,
        
        [:init_code_hash, :source_code].to_set,
        [:init_code_hash, :source_code, :args].to_set
      ].include?(data_keys)
        raise InvalidEthscriptionError.new("Invalid data keys: #{data_keys}")
      end
    end
    
    if [:call, :static_call].include?(op)
      unless [
        [:to, :function].to_set,
        [:to, :function, :args].to_set
      ].include?(data_keys)
        raise InvalidEthscriptionError.new("Invalid data keys: #{data_keys}")
      end
      
      unless payload.data['to'].to_s.match(/\A0x[a-f0-9]{40}\z/i)
        raise InvalidEthscriptionError.new("Invalid to address: #{payload.data['to']}")
      end
    end
  end
  
  def initial_call
    contract_calls.sort_by(&:internal_transaction_index).first
  end
  
  def build_transaction_receipt
    self.transaction_receipt = TransactionReceipt.new(
      transaction_hash: transaction_hash,
      call_type: initial_call.call_type,
      block_number: block_number,
      block_blockhash: block_blockhash,
      transaction_index: transaction_index,
      from_address: initial_call.from_address,
      block_timestamp: block_timestamp,
      function: initial_call.function,
      args: initial_call.args,
      logs: contract_calls.sort_by(&:internal_transaction_index).map(&:logs).flatten,
      return_value: initial_call.return_value,
      status: status,
      effective_contract_address: initial_call.effective_contract_address,
      error: initial_call.error,
      runtime_ms: initial_call.calculated_runtime_ms,
      gas_price: ethscription.gas_price,
      gas_used: ethscription.gas_used,
      transaction_fee: ethscription.transaction_fee,
    )
  end
  
  def self.simulate_transaction(from:, tx_payload:)
    cache_key = [
      :simulate_transaction,
      ContractState.all,
      SystemConfigVersion.all,
      EthBlock.all,
      from,
      tx_payload
    ]
  
    Rails.cache.fetch(cache_key) do
      mimetype = ContractTransaction.transaction_mimetype
      uri = %{#{mimetype},#{tx_payload.to_json}}
  
      block_number = EthBlock.maximum(:block_number).to_i + 1
      
      ethscription_attrs = {
        transaction_hash: "0x" + SecureRandom.hex(32),
        block_number: block_number,
        block_blockhash: "0x" + SecureRandom.hex(32),
        creator: from.downcase,
        block_timestamp: Time.zone.now.to_i,
        transaction_index: 1,
        content_uri: uri,
        initial_owner: "0x" + "0" * 40,
        mimetype: mimetype,
        processing_state: "pending"
      }
      
      eth = Ethscription.new(ethscription_attrs)
      
      eth.process!(persist: false)
      
      {
        transaction_receipt: eth.contract_transaction&.transaction_receipt,
        ethscription_status: eth.processing_state,
        ethscription_error: eth.processing_error,
    }.with_indifferent_access
    end
  end
  
  def self.make_static_call(
    contract:,
    function_name:,
    function_args: {},
    msgSender: nil,
    block_timestamp: EthBlock.maximum(:timestamp) + 12,
    block_number: EthBlock.maximum(:block_number) + 1
  )
    cache_key = [:make_static_call, ContractState.all, contract, function_name, function_args, msgSender]
    
    Rails.cache.fetch(cache_key) do
      record = new(
        tx_origin: msgSender,
        block_timestamp: block_timestamp,
        block_number: block_number
      )
      
      record.payload = OpenStruct.new(
        op: :static_call,
        data: {
          function: function_name,
          args: function_args,
          to: contract
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
      system_config: SystemConfigVersion.current,
      call_stack: CallStack.new(TransactionContext),
      current_transaction: self,
      tx_origin: tx_origin,
      tx_current_transaction_hash: transaction_hash,
      block_number: block_number,
      block_timestamp: block_timestamp,
      block_blockhash: block_blockhash,
      transaction_index: transaction_index
    ) do
      yield
    end
  end
  
  def make_initial_call
    with_global_context do
      payload_data = OpenStruct.new(payload.data)
      
      TransactionContext.call_stack.execute_in_new_frame(
        to_contract_init_code_hash: payload_data.init_code_hash,
        to_contract_source_code: payload_data.source_code,
        to_contract_address: payload_data.to&.downcase,
        function: payload_data.function,
        args: payload_data.args,
        type: payload.op.to_sym,
      )
    end
  end
  
  def execute_transaction(persist:)
    validate_payload!
    
    if persist && payload.op.to_sym == :static_call
      raise InvalidEthscriptionError.new("Static calls cannot be persisted")
    end
    
    begin
      make_initial_call
    rescue ContractError, TransactionError
    end
    
    build_transaction_receipt
    
    if persist
      ContractTransaction.transaction do
        save!
        persist_contract_state_if_success!
      end
    end
  end
  
  def persist_contract_state_if_success!
    return unless status == :success
    
    grouped_contracts = contract_calls.group_by { |call| call.to_contract.address }

    grouped_contracts.each do |address, calls|
      states = calls.map { |call| call.to_contract.current_state }.uniq
      if states.length > 1
        raise "Duplicate contracts with different states for address #{address}"
      end
    end
    
    contract_calls.map(&:to_contract).uniq(&:address).each do |contract|
      contract.save_new_state_if_needed!(
        transaction: self,
      )
    end
  end
  
  def get_active_contract(address)
    contract_calls.detect do |call|
      call.to_contract&.address == address
    end&.to_contract
  end
  
  def status
    contract_calls.any?(&:failure?) ? :failure : :success
  end
end
