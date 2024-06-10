class Contract < ApplicationRecord
  include FacetRailsCommon::OrderQuery
  include ContractErrors
  
  initialize_order_query({
    newest_first: [
      [:block_number, :desc],
      [:transaction_index, :desc],
      [:created_at, :desc, unique: true]
    ],
    oldest_first: [
      [:block_number, :asc],
      [:transaction_index, :asc],
      [:created_at, :asc, unique: true]
    ]
  }, page_key_attributes: [:address])
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  belongs_to :contract_artifact, foreign_key: :current_init_code_hash, primary_key: :init_code_hash, optional: true
  
  has_many :contract_calls, foreign_key: :effective_contract_address, primary_key: :address
  has_one :transaction_receipt, through: :contract_transaction

  def self.cache_all_state
    find_each do |contract|
      contract.cache_state
    end
  end
  
  def cache_state(block_number = TransactionReceipt.maximum(:block_number))
    Contract.transaction do
      structure = state_manager.build_structure
      contract = self
      
      # if contract.current_state != structure
        contract.update!(current_state: structure)
      
        state = ContractState.find_or_initialize_by(
          contract_address: address,
          block_number: block_number
        )
        
        state.type ||= contract.current_type
        state.init_code_hash ||= contract.current_init_code_hash
        state.state = structure
        
        state.save!
      # end
    end
  end
  
  def stored_implementation_class
    unless current_init_code_hash
      raise ContractError.new("Contract has no init code hash", self)
    end
    
    # if current_type == "NameRegistry"
    #   if Rails.env.development?
    #     c = RubidityTranspiler.hack_get("NameRegistry01")&.build_class
    #     ap c
    #     return c
    #   end
    # end
    
    BlockContext.supported_contract_class(
      current_init_code_hash,
      validate: false
    )
  end
  
  def state_manager
    @_state_manager ||= StateManager.new(
      self,
      stored_implementation_class.state_var_def_json
    )
  end
  
  # TODO: make work
  def fresh_implementation_with_current_state
    implementation_class.new(initial_state: current_state)
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
      if association(:transaction_receipt).loaded?
        json['deployment_transaction'] = transaction_receipt
      end
      
      json['current_state'] = if options[:include_current_state]
        current_state
      else
        {}
      end
      
      if ApiResponseContext.use_v1_api?
        json['current_state']['contract_type'] = current_type
      end
      
      json['abi'] = contract_artifact&.build_class&.abi.as_json
        
      json['source_code'] = [
        {
          language: 'ruby',
          code: contract_artifact&.source_code
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
  
  def self.get_storage_value_by_path(contract_address, path)
    NewContractState.where(contract_address: contract_address).
      where("key = ?", path.to_json).pick(:value)
  end
end