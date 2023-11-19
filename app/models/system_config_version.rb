class SystemConfigVersion < ApplicationRecord
  include ContractErrors  
  
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash',
  touch: true, optional: true
  
  PERMISSIONED_ADDRESS = "0xc2172a6315c1d7f6855768f843c420ebb36eda97"
  
  scope :newest_first, -> {
    order(block_number: :desc, transaction_index: :desc) 
  }
  
  def self.system_mimetype
    "application/vnd.facet.system+json"
  end
  
  def self.create_from_ethscription!(ethscription)
    record = current.deep_dup
    record.ethscription = ethscription
    
    record.perform_operation!
  end
  
  def perform_operation!
    raise "Already performed" unless new_record?
    
    return unless valid_ethscription?
    
    operations = {
      'updateSupportedContracts' => :update_supported_contracts!,
      'updateStartBlockNumber' => :update_start_block_number!
    }
  
    operation = ethscription.parsed_content['op']
    method_name = operations[operation]
  
    if method_name
      send(method_name)
    else
      Rails.logger.info "Unexpected op: #{operation}"
    end
  end
  
  def operation_data
    JSON.parse(ethscription.content).fetch('data')
  end
  
  def ethscription=(ethscription)
    unless new_record?
      raise "Cannot change ethscription on existing record"
    end
    
    assign_attributes(
      transaction_hash: ethscription.transaction_hash,
      block_number: ethscription.block_number,
      transaction_index: ethscription.transaction_index,
    )
    
    super(ethscription)
  end
  
  def self.current
    (newest_first.first || new).freeze
  end
  
  def contract_supported?(init_code_hash)
    supported_contracts.include?(init_code_hash)
  end
  
  def self.current_supported_contract_artifacts
    artifacts = Rails.cache.fetch([all]) do
      current.supported_contracts.map do |item|
        begin
          RubidityTranspiler.find_and_transpile(item)
        rescue UnknownInitCodeHash => e
          ContractArtifact.find_by_init_code_hash!(item)
        end
      end
    end.deep_dup
    
    artifacts.each(&:set_abi)
    artifacts
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :supported_contracts,
          :block_number,
          :transaction_index,
        ]
      )
    )
  end
  
  private
  
  def update_supported_contracts!
    data = operation_data
      
    unless data.is_a?(Array) && data.all? { |el| el.to_s =~ /\A0x[a-f0-9]{64}\z/ }
      raise "Invalid data: #{data.inspect}"
    end
    
    update!(supported_contracts: data.uniq)
  end
  
  def update_start_block_number!
    old_number = self.class.current.start_block_number
    new_number = operation_data
    
    unless new_number.is_a?(Integer)
      raise "Invalid data: #{new_number.inspect}"
    end
    
    if old_number && (block_number >= old_number)
      raise "Can't set start block after already started"
    end
    
    unless new_number > block_number
      raise "Start block must be in the future"
    end
    
    update!(start_block_number: new_number)
  end
  
  def valid_ethscription?
    if ethscription.creator != PERMISSIONED_ADDRESS
      Rails.logger.info "Unexpected from: #{ethscription.from}"
      return
    end
    
    if ethscription.initial_owner != "0x" + "0" * 40
      Rails.logger.info "Unexpected initial_owner: #{ethscription.initial_owner}"
      return
    end
    
    if ethscription.mimetype != self.class.system_mimetype
      Rails.logger.info "Unexpected mimetype: #{ethscription.mimetype}"
      return
    end
    
    true
  end
end
