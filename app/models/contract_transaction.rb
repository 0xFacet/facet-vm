class ContractTransaction
  include ContractErrors
  
  NULL_ADDRESS = ("0x" + "0" * 40).freeze
  
  attr_accessor :contract_address, :function_name, :contract_type,
  :function_args, :tx, :esc, :call_receipt, :ethscription, :operation, :block,
  :current_contract
  
  def self.required_mimetype
    "application/vnd.esc"
  end
  
  def tx
    @tx ||= ContractTransactionGlobals::Tx.new
  end
  
  def block
    @block ||= ContractTransactionGlobals::Block.new(self)
  end
  
  def esc
    @esc ||= ContractTransactionGlobals::Esc.new(self)
  end
  
  def self.create_and_execute_from_ethscription_if_needed(ethscription)
    begin
      new.import_from_ethscription(ethscription)&.execute_transaction
    rescue EthscriptionDoesNotTriggerContractInteractionError => e
      Rails.logger.info(e.message)
    end
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
    
    call_receipt = nil
  
    ActiveRecord::Base.transaction do
      eth = Ethscription.create!(ethscription_attrs)
      call_receipt = eth.contract_call_receipt
  
      raise ActiveRecord::Rollback
    end
  
    call_receipt
  end
  
  def call_with_args_parsed_from_external_json
    if function_args.is_a?(Array)
      initial_contract_proxy.send(function_name, *function_args)
    elsif function_args.is_a?(Hash)
      initial_contract_proxy.send(function_name, **function_args)
    else
      initial_contract_proxy.send(function_name, function_args)
    end
  end
  
  def self.make_static_call(contract:, function_name:, function_args: {}, msgSender: nil)
    new(
      operation: :static_call,
      function_name: function_name,
      function_args: function_args,
      contract_address: contract,
      msgSender: msgSender
    ).execute_static_call.as_json
  end
  
  def initialize(options = {})
    @operation = options[:operation]
    @function_name = options[:function_name]
    @function_args = options[:function_args]
    @contract_address = options[:contract_address]
    tx.origin = options[:msgSender]
  end
  
  def import_from_ethscription(ethscription)
    unless ethscription.initial_owner == NULL_ADDRESS && ethscription.mimetype == ContractTransaction.required_mimetype
      raise EthscriptionDoesNotTriggerContractInteractionError.new(
        "#{ethscription.inspect} does not trigger contract interaction"
      )
    end
    
    self.ethscription = ethscription
    
    self.call_receipt = ContractCallReceipt.new(
      caller: ethscription.creator,
      ethscription_id: ethscription.ethscription_id,
      timestamp: ethscription.creation_timestamp
    )
    
    begin
      payload = JSON.parse(ethscription.content)
      data = payload['data']
    rescue JSON::ParserError => e
      call_receipt.update!(
        status: :json_parse_error,
        error_message: "JSON::ParserError: #{e.message}"
      )
      
      return
    end
    
    self.operation = payload['to'].nil? ? :deploy : :call
    
    self.function_name = is_deploy? ? :constructor : data['function']
    self.function_args = data['args'] || {}
    self.contract_address = payload['to']
    self.contract_type = data['type']
    
    call_receipt.assign_attributes(
      function_name: function_name,
      function_args: function_args
    )
    
    tx.origin = ethscription.creator
    
    block.number = ethscription.block_number
    block.timestamp = ethscription.creation_timestamp.to_i
    
    unless function_name
      raise EthscriptionDoesNotTriggerContractInteractionError.new(
        "#{ethscription.inspect} does not trigger contract interaction"
      )
    end
    
    self
  end
  
  def create_execution_context_for_call(callee_contract_address, caller_address)
    callee_contract = Contract.find_by_address(callee_contract_address.to_s)
    
    if callee_contract.blank?
      raise CallingNonExistentContractError.new("Contract not found: #{callee_contract_address}")
    end
    
    callee_contract.msg.sender = caller_address
    callee_contract.current_transaction = self
    
    self.current_contract = callee_contract
    
    ContractProxy.new(callee_contract, operation: operation)
  end
  
  def ensure_valid_deploy!
    return unless is_deploy? && contract_address.blank?
    
    new_contract = Contract.create_from_user!(
      creation_ethscription_id: ethscription.ethscription_id,
      deployer: tx.origin,
      type: contract_type,
    )
    
    self.contract_address = new_contract.address
  end
  
  def initial_contract_proxy
    @initial_contract_proxy ||= create_execution_context_for_call(contract_address, tx.origin)
  end
  
  def execute_static_call
    begin
      call_with_args_parsed_from_external_json
    rescue ContractError => e
      raise StaticCallError.new("Static Call error #{e.message}")
    end
  end
  
  def execute_transaction
    begin
      ActiveRecord::Base.transaction(requires_new: true) do
        ensure_valid_deploy!
        
        call_with_args_parsed_from_external_json.tap do
          call_receipt.status = :success
          call_receipt.contract_address = contract_address
          
          call_receipt.save!
        end
      end
    rescue ContractError, TransactionError => e
      call_receipt.error_message = e.message
      call_receipt.status = if is_deploy?
        :deploy_error
      else
        e.is_a?(CallingNonExistentContractError) ? :call_to_non_existent_contract : :call_error
      end
      
      call_receipt.contract_address = contract_address
      if is_deploy? || e.is_a?(CallingNonExistentContractError)
        call_receipt.contract_address = nil
      end
      
      call_receipt.save!
    end
  end
  
  def is_deploy?
    operation == :deploy
  end
  
  def log_event(event)
    call_receipt.logs << event
    event
  end
end
