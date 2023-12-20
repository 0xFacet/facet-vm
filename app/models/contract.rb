class Contract < ApplicationRecord
  include ContractErrors
    
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  has_many :contract_calls, foreign_key: :effective_contract_address, primary_key: :address
  has_one :transaction_receipt, through: :contract_transaction

  attr_reader :implementation
  
  delegate :implements?, to: :implementation
  
  after_initialize :set_normalized_initial_state
  
  def set_normalized_initial_state
    @normalized_initial_state = JsonSorter.sort_hash(current_state)
  end
  
  def normalized_state_changed?
    @normalized_initial_state != JsonSorter.sort_hash(current_state)
  end
  
  def implementation_class
    return unless current_init_code_hash
    
    TransactionContext.supported_contract_class(
      current_init_code_hash, validate: false
    )
  end
  
  def self.types_that_implement(base_type)
    ContractArtifact.types_that_implement(base_type)
  end
  
  def should_save_new_state?
    current_init_code_hash_changed? ||
    current_type_changed? ||
    normalized_state_changed?
  end
  
  def save_new_state_if_needed!(transaction:)
    return unless should_save_new_state?
    
    states.create!(
      transaction_hash: transaction.transaction_hash,
      block_number: transaction.block_number,
      transaction_index: transaction.transaction_index,
      state: current_state,
      type: current_type,
      init_code_hash: current_init_code_hash
    )
  end
  
  def execute_function(function_name, args, is_static_call:)
    with_correct_implementation do
      if !implementation.public_abi[function_name]
        raise ContractError.new("Call to unknown function: #{function_name}", self)
      end
      
      read_only = implementation.public_abi[function_name].read_only?
      
      if is_static_call && !read_only
        raise ContractError.new("Cannot call non-read-only function in static call: #{function_name}", self)
      end
      
      result = if args.is_a?(Hash)
        implementation.public_send(function_name, **args)
      else
        implementation.public_send(function_name, *Array.wrap(args))
      end
      
      unless read_only
        self.current_state = self.current_state.merge(implementation.state_proxy.serialize)
      end
      
      result
    end
  end
  
  def with_correct_implementation
    old_implementation = implementation
    @implementation = implementation_class.new(
      initial_state: old_implementation&.state_proxy&.serialize ||
        current_state
    )
    
    result = yield
    
    if old_implementation
      @implementation = old_implementation
      implementation.state_proxy.load(current_state)
    end
    
    result
  end
  
  def fresh_implementation_with_current_state
    implementation_class.new(initial_state: current_state)
  end
  
  def self.deployable_contracts
    ContractArtifact.deployable_contracts
  end
  
  def self.all_abis(...)
    ContractArtifact.all_abis(...)
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :address,
          :transaction_hash,
          :current_init_code_hash,
          :current_type
        ]
      )
    ).tap do |json|
      if implementation_class
        json['abi'] = implementation_class.abi.as_json
      end
      
      if association(:transaction_receipt).loaded?
        json['deployment_transaction'] = transaction_receipt
      end
      
      json['current_state'] = if options[:include_current_state]
        current_state
      else
        {}
      end
      
      json['current_state']['contract_type'] = current_type
      
      json['source_code'] = [
        {
          language: 'ruby',
          code: implementation_class&.source_code
        }
      ]
    end
  end
  
  def static_call(name, args = {})
    ContractTransaction.make_static_call(
      contract: address, 
      function_name: name, 
      function_args: args
    )
  end

  
  
#   def self.check_erc20_bridge
#     block_number = 18786816

#     c = ContractState.where(
#       contract_address: "0x55ab0390a89fed8992e3affbf61d102490735e24",
#     ).where("block_number <= ?", block_number).newest_first.first;nil
    
    
#     bi = TransactionReceipt.where(
#       status: "success",
#       to_contract_address: "0x55ab0390a89fed8992e3affbf61d102490735e24",
#       function: "bridgeIn"
#     ).where("block_number <= ?", block_number); nil
    
#     bi_amount = bi.map do |tx|
#       tx.logs.detect{|l| l['event'] == "BridgedIn" }['data']['amount']
#     end.sum
    
#     bi_amount = bi.map do |tx|
#       tx.logs.detect{|l| l['event'] == "BridgedIn" }['data']['amount']
#     end.sum
    
#     bo = TransactionReceipt.where(
#       status: "success",
#       to_contract_address: "0x55ab0390a89fed8992e3affbf61d102490735e24",
#       function: "bridgeOut"
#     ).where("block_number <= ?", block_number); nil
    
#     bo_amount = bo.map do |tx|
#       tx.logs.detect{|l| l['event'] == "InitiateWithdrawal" }['data']['amount']
#     end.sum
    
#     wc = TransactionReceipt.where(
#       status: "success",
#       to_contract_address: "0x55ab0390a89fed8992e3affbf61d102490735e24",
#       function: "markWithdrawalComplete"
#     ).where("block_number <= ?", block_number); nil
    
#     wc_amount = wc.map do |tx|
#       tx.logs.detect{|l| l['event'] == "WithdrawalComplete" }['data']['amount']
#     end.sum
    
#     supply = c.state['totalSupply']
#     pending_withdraw = c.state['withdrawalIdAmount'].values.sum

    
#     list.select do |address, on_contract_count|
#       bridged_in_for_address = bi.select do |tx|
#         tx.logs.detect{|l| l['event'] == "BridgedIn" }['data']['to'] == address
#       end
      
#       bi_amount = bridged_in_for_address.sum{|i| i.logs.detect{|l| l['event'] == "BridgedIn" }['data']['amount']}
      
#       complete_for_address = wc.select do |tx|
#         tx.logs.detect{|l| l['event'] == "WithdrawalComplete" }['data']['to'] == address
#       end
      
#       c_amount = complete_for_address.sum{|i| i.logs.detect{|l| l['event'] == "WithdrawalComplete" }['data']['amount']}
      
#       on_contract_count != bi_amount - c_amount
#     end
    
#     (3144 * 1000).ether - (supply + (pending_withdraw * 1000).ether)
    
#     on_contract - (pending deposits + supply + pending_withdrawals)
    
    
    
#     # pending_deposits = on_contract_count - total_bridged_in - total_confirmed_out
    
#     pending_deposits = on_contract_count - completed_deposits - completed_withdrawals
    
#     total_supply + pending_withdraw + pending_deposits = on_contract_count
    
    
    
#     0 = total_supply + pending_withdraw + pending_deposits - completed_deposits - completed_withdrawals - on_contract_count
    
    
#     # 0 = total_supply + pending_withdraw - completed_deposits - completed_withdrawals
    
#     end
  
  
#   def self.check_supply
#     block_number = EthBlock.max_processed_block_number
#     sc_balanace = 3404155726647544476835
#     ether_bridge_address = "0x1673540243e793b0e77c038d4a88448eff524dce".downcase
    
#     c = ContractState.where(
#       contract_address: ether_bridge_address,
#     ).where("block_number <= ?", block_number).newest_first.first
    
#     supply = c.state['totalSupply']
#     pending_withdraw = c.state['withdrawalIdAmount'].values.sum
    
#     # marked_complete = TransactionReceipt.where(
#     #   status: "success",
#     #   to_contract_address: "0x1673540243e793b0e77c038d4a88448eff524dce",
#     #   function: "markWithdrawalComplete"
#     # )
      
#     # mc_total = marked_complete.map do |r|
#     #   r.logs.first['data']['amount']
#     # end.sum
    
#     # total_bridged_in - (supply + mc_total + pending_withdraw)
#     # supply + pending_withdraw
#     diff = sc_balanace - (supply + pending_withdraw)
    
#     if diff.abs > 0.5.ether
#       raise "Supply mismatch: #{supply} + #{pending_withdraw} + #{diff} != #{sc_balanace}"
#     end
#   end 
  
  
  
  
  
 

 
 
  
  
  
end
