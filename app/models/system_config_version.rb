class SystemConfigVersion < ApplicationRecord
  include ContractErrors  
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  belongs_to :ethscription,
  primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  scope :newest_first, -> {
    order(block_number: :desc, transaction_index: :desc) 
  }
  
  attr_accessor :all_contracts_supported
  
  def self.latest_tx_hash
    newest_first.limit(1).pluck(:transaction_hash).first
  end
  
  def self.system_mimetype
    "application/vnd.facet.system+json"
  end
  
  def self.create_from_ethscription!(ethscription, persist:)
    current.deep_dup.tap do |config_version|
      config_version.ethscription = ethscription
    
      config_version.perform_operation!(persist: persist)
    end
  end
  
  def perform_operation!(persist:)
    raise "Already performed" unless new_record?
    
    if ethscription.creator != self.class.current_admin_address
      raise InvalidEthscriptionError.new("Only admin can update system config")
    end
    
    operations = {
      'updateSupportedContracts' => :update_supported_contracts,
      'updateStartBlockNumber' => :update_start_block_number,
      'updateAdminAddress' => :update_admin_address
    }
  
    operation = ethscription.parsed_content['op']
    method_name = operations[operation]
  
    if method_name
      send(method_name)
    else
      raise InvalidEthscriptionError.new("Unexpected op: #{operation}")
    end
    
    save! if persist
  end
  
  def operation_data
    JSON.parse(ethscription.content).fetch('data')
  rescue JSON::ParserError => e
    raise InvalidEthscriptionError.new("JSON parse error: #{e.message}")
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
    ENV['ALL_CONTRACTS_SUPPORTED'] == 'true' ||
    all_contracts_supported ||
    supported_contracts.include?(init_code_hash)
  end
  
  def self.current_supported_contract_artifacts
    artifacts = Rails.cache.fetch(["current_supported_contract_artifacts", all]) do
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
  
  def self.current_admin_address
    current.admin_address || ENV.fetch("INITIAL_SYSTEM_CONFIG_ADMIN_ADDRESS").downcase
  end
  
  private
  
  def update_admin_address
    new_address = operation_data
    
    unless new_address.is_a?(String) && new_address =~ /\A0x[a-f0-9]{40}\z/i
      raise InvalidEthscriptionError.new("Invalid data: #{operation_data.inspect}")
    end
    
    if new_address == self.class.current_admin_address
      raise InvalidEthscriptionError.new("No change to admin address proposed")
    end
    
    assign_attributes(admin_address: new_address.downcase)
  end
  
  def update_supported_contracts
    data = operation_data
      
    unless data.is_a?(Array) && data.all? { |el| el.to_s =~ /\A0x[a-f0-9]{64}\z/ }
      raise InvalidEthscriptionError.new("Invalid data: #{operation_data.inspect}")
    end
    
    if data == self.class.current.supported_contracts
      raise InvalidEthscriptionError.new("No change to supported contracts proposed")
    end
    
    assign_attributes(supported_contracts: data.uniq)
  end
  
  def update_start_block_number
    old_number = self.class.current.start_block_number
    new_number = operation_data
    
    if new_number == old_number
      raise InvalidEthscriptionError.new("Start block already set to #{new_number}")
    end
    
    unless new_number.is_a?(Integer)
      raise InvalidEthscriptionError.new("Invalid data: #{new_number.inspect}")
    end
    
    if old_number && (block_number >= old_number)
      raise InvalidEthscriptionError.new("Can't set start block after already started")
    end
    
    unless new_number > block_number
      raise InvalidEthscriptionError.new("Start block must be in the future")
    end
    
    assign_attributes(start_block_number: new_number)
  end
end
