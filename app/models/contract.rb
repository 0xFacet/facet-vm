class Contract < ApplicationRecord
  self.inheritance_column = :_type_disabled
  
  include ContractErrors
    
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  has_one :newest_state, -> { newest_first }, class_name: 'ContractState', primary_key: 'address',
    foreign_key: 'contract_address'
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  belongs_to :ethscription, primary_key: 'ethscription_id', foreign_key: 'transaction_hash', optional: true
  
  has_many :contract_calls, foreign_key: :effective_contract_address, primary_key: :address
  has_many :contract_transactions, through: :contract_calls
  has_many :contract_transaction_receipts, through: :contract_transactions
  
  has_one :creating_contract_call, class_name: 'ContractCall', foreign_key: 'created_contract_address', primary_key: 'address'

  attr_reader :implementation
  
  delegate :implements?, to: :implementation
  
  def implementation
    @implementation ||= implementation_class.new
  end
  
  # TODO this should always look to TransactionContext if in a transaction
  # We need to give contracts a context
  def implementation_class
    klass = TransactionContext.implementation_from_init_code(init_code_hash) || RubidityFile.registry[init_code_hash]
    
    if !klass && Rails.env.development?
      klass = TransactionContext.implementation_from_type(type)
    end
    
    klass
  end
  
  def self.types_that_implement(base_type)
    impl = RubidityFile.registry.values.detect{|i| i.name == base_type.to_s}
    
    RubidityFile.registry.values.reject(&:is_abstract_contract).select do |contract|
      contract.implements?(impl)
    end
  end
  
  def execute_function(function_name, args)
    with_state_management do
      if args.is_a?(Hash)
        implementation.public_send(function_name, **args)
      else
        implementation.public_send(function_name, *Array.wrap(args))
      end
    end
  end
  
  def with_state_management
    state_changed = false
    
    implementation.state_proxy.load(latest_state.deep_dup)
    initial_state = implementation.state_proxy.serialize.deep_dup
    
    result = yield.tap do
      final_state = implementation.state_proxy.serialize
      
      if final_state != initial_state
        states.create!(
          transaction_hash: TransactionContext.transaction_hash,
          block_number: TransactionContext.block_number,
          transaction_index: TransactionContext.transaction_index,
          internal_transaction_index: TransactionContext.current_call.internal_transaction_index,
          state: final_state
        )
        
        state_changed = true
      end
    end
    
    { result: result, state_changed: state_changed }
  end
  
  def fresh_implementation_with_latest_state
    implementation_class.new.tap do |implementation|
      implementation.state_proxy.load(latest_state.deep_dup)
    end
  end
  
  def self.deployable_contracts
    RubidityFile.registry.values.reject(&:is_abstract_contract)
  end
  
  def self.all_abis(deployable_only: false)
    contract_classes = RubidityFile.registry.values.dup
    contract_classes.reject!(&:is_abstract_contract) if deployable_only
    
    contract_classes.each_with_object({}) do |contract_class, hash|
      hash[contract_class.name] = contract_class.public_abi
    end
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :address,
          :transaction_hash,
        ]
      )
    ).tap do |json|
      json['abi'] = implementation.public_abi.map do |name, func|
        [name, func.as_json.except('implementation')]
      end.to_h
      
      json['current_state'] = if options[:include_current_state]
        latest_state
      else
        {}
      end
      
      json['current_state']['contract_type'] = type
      
      klass = implementation.class
      
      json['source_code'] = [
        {
          language: 'ruby',
          code: klass.source_code
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
end
