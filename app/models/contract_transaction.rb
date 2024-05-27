class ContractTransaction < ApplicationRecord
  include ContractErrors
  
  belongs_to :ethscription, primary_key: :transaction_hash, foreign_key: :transaction_hash, optional: true
  has_many :contract_states, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contracts, foreign_key: :transaction_hash, primary_key: :transaction_hash
  has_many :contract_artifacts, foreign_key: :transaction_hash, primary_key: :transaction_hash
  
  has_one :transaction_receipt, foreign_key: :transaction_hash, primary_key: :transaction_hash, inverse_of: :contract_transaction
  has_many :contract_calls, foreign_key: :transaction_hash, primary_key: :transaction_hash, inverse_of: :contract_transaction
  
  attr_accessor :tx_origin, :payload
  
  def self.transaction_mimetype
    "application/vnd.facet.tx+json"
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
    
    validate_payload!
    
    super(ethscription)
  end
  
  def validate_payload!
    unless BlockContext.start_block_passed?
      raise InvalidEthscriptionError.new("Start block not passed")
    end
    
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
    contract_calls.target.sort_by(&:internal_transaction_index).first
  end
  
  def computed_logs
    return [] if failure?
    contract_calls.target.flat_map(&:logs).sort_by { |log| log['log_index'] }
  end
  
  def transaction_receipt_for_import
    base_attrs = {
      transaction_hash: transaction_hash,
      block_number: block_number,
      block_blockhash: block_blockhash,
      transaction_index: transaction_index,
      block_timestamp: block_timestamp,
      logs: computed_logs,
      status: status,
      runtime_ms: initial_call.calculated_runtime_ms,
      gas_price: ethscription.gas_price,
      gas_used: ethscription.gas_used,
      transaction_fee: ethscription.transaction_fee
    }
    
    base_attrs[:function_stats] = @call_counts
    base_attrs[:facet_gas_used] = @total_gas_used
    base_attrs[:gas_stats] = @gas_stats
    
    call_attrs = initial_call.attributes.with_indifferent_access.slice(
      :to_contract_address,
      :created_contract_address,
      :effective_contract_address,
      :call_type,
      :from_address,
      :function,
      :args,
      :return_value,
      :error
    )
    
    attrs = base_attrs.merge(call_attrs)
    
    TransactionReceipt.new(attrs)
  end
  
  def self.simulate_transaction_with_state(from:, tx_payload:, initial_state: {})
    state_defining_model_names = [
      'EthBlock',
      'Ethscription',
      'ContractTransaction',
      'ContractCall',
      'ContractArtifact',
      'Contract',
      'NewContractState',
    ]
    
    with_temporary_database_environment do
      initial_state.each do |model_name, records|
        model_class_name = model_name.to_s.classify
        
        if state_defining_model_names.exclude?(model_class_name)
          raise "Invalid model name: #{model_name}"
        end
        
        model_class = model_class_name.constantize
        instances = records.map { |record_attrs| model_class.new(record_attrs) }
        model_class.import!(instances)
      end
      
      sim_res = simulate_transaction(
        from: from,
        tx_payload: tx_payload,
        persist: true,
        no_cache: true,
        config_version: SystemConfigVersion.new(
          start_block_number: 0,
          all_contracts_supported: true
        )
      )
      
      Contract.cache_all_state
      
      state = state_defining_model_names.each.with_object({}) do |model_name, hash|
        model_class = model_name.constantize
        key = model_name.underscore.pluralize.to_sym
        hash[key] = model_class.all.map { |instance| instance.attributes.as_json }
      end.with_indifferent_access
      
      sim_res.merge(state: state).with_indifferent_access
    end
  end
  
  def self.simulate_transaction(
    from:,
    tx_payload:,
    persist: false,
    no_cache: false,
    config_version: SystemConfigVersion.current
  )
    max_block_number = Rails.cache.fetch(
      "EthBlock.max_processed_block_number",
      expires_in: 1.second
    ) do
      EthBlock.max_processed_block_number
    end
    
    cache_key = [
      config_version,
      max_block_number,
      from,
      tx_payload,
      (no_cache ? rand : nil)
    ].to_cache_key(:simulate_transaction)
    
    cache_key = Digest::SHA256.hexdigest(cache_key)
  
    Rails.cache.fetch(cache_key) do
      mimetype = ContractTransaction.transaction_mimetype
      uri = %{data:#{mimetype};rule=esip6,#{tx_payload.to_json}}
      
      current_block = EthBlock.new(
        block_number: max_block_number + 1,
        timestamp: Time.zone.now.to_i,
        blockhash: "0x" + SecureRandom.hex(32),
        parent_blockhash: EthBlock.most_recently_imported_blockhash || "0x" + SecureRandom.hex(32),
        imported_at: Time.zone.now,
        processing_state: "complete",
        transaction_count: 1,
        runtime_ms: 1,
      )
      
      current_block.save! if persist
      
      ethscription_attrs = {
        transaction_hash: "0x" + SecureRandom.hex(32),
        block_number: current_block.block_number,
        block_blockhash: current_block.blockhash,
        creator: from&.downcase,
        block_timestamp: current_block.timestamp,
        transaction_index: 1,
        content_uri: uri,
        initial_owner: Ethscription.required_initial_owner,
        mimetype: mimetype,
        processing_state: "pending"
      }
      
      eth = Ethscription.new(ethscription_attrs)
      
      eth.save! if persist
      
      BlockBatchContext.set(
        contracts: {},
        contract_classes: {}
      ) do
        BlockContext.set(
          system_config: config_version,
          current_block: current_block,
          contracts: [],
          contract_artifacts: [],
          ethscriptions: [eth],
          current_log_index: 0
        ) do
          BlockContext.process_contract_transactions(persist: persist)
        end
      end
      
      {
        transaction_receipt: eth.contract_transaction&.transaction_receipt_for_import,
        internal_transactions: eth.contract_transaction&.contract_calls&.target&.map(&:as_json),
        ethscription_status: eth.processing_state,
        ethscription_error: eth.processing_error,
        ethscription_content_uri: uri
      }.with_indifferent_access
    end
  end
  
  def self.make_static_call(
    contract:,
    function_name:,
    function_args: {},
    msgSender: nil
  )
    simulate_transaction_result = simulate_transaction(
      from: msgSender,
      tx_payload: {
        op: :static_call,
        data: {
          function: function_name,
          args: function_args,
          to: contract
        }
      }
    )
  
    receipt = simulate_transaction_result[:transaction_receipt]
    
    if receipt.status != 'success'
      raise StaticCallError.new("Static Call error #{receipt.error}")
    end
    
    receipt.return_value
  end
  
  def with_global_context
    TransactionContext.set(
      call_stack: CallStack.new(TransactionContext),
      gas_counter: GasCounter.new(TransactionContext),
      active_contracts: [],
      current_transaction: self,
      tx_origin: tx_origin,
      tx_current_transaction_hash: transaction_hash,
      block_number: block_number,
      block_timestamp: block_timestamp,
      block_blockhash: block_blockhash,
      block_chainid: BlockContext.current_chainid,
      transaction_index: transaction_index,
      call_counts: {},
      call_log_stack: [],
    ) do
      yield
    end
  end
  
  def make_initial_call
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
  
  def execute_transaction
    begin
      make_initial_call
    rescue ContractError, TransactionError => e
    end
    
    @call_counts = TransactionContext.call_counts
    @total_gas_used = TransactionContext.gas_counter.total_gas_used
    @gas_stats = TransactionContext.gas_counter.per_event_gas_used
    
    if success?
      TransactionContext.active_contracts.each do |c|
        c.state_manager.commit_transaction
      end
    else
      TransactionContext.active_contracts.each do |c|
        c.state_manager.rollback_transaction
      end
      
      clean_up_failed_contracts
    end
  end
  
  def clean_up_failed_contracts
    return unless failure?
    
    contract_calls.select do |call|
      call.internal_transaction_index > 0
    end.each do |call|
      BlockContext.remove_contract(call.created_contract)
      
      call.assign_attributes(
        created_contract: nil,
        effective_contract: nil
      )
    end
  end
  
  def success?
    status == :success
  end
  
  def failure?
    !success?
  end
  
  def status
    failed = contract_calls.target.any? do |call|
      call.failure? && !call.in_low_level_call_context
    end
    
    failed ? :failure : :success
  end
end
