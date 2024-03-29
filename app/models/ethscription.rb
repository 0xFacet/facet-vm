class Ethscription < ApplicationRecord
  include ContractErrors
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true, autosave: false
  
  has_many :contracts, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', autosave: false
  has_one :transaction_receipt, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', autosave: false

  has_one :contract_transaction, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', autosave: false
  has_one :system_config_version, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', autosave: false
  has_many :contract_states, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', autosave: false
  
  before_validation :downcase_hex_fields
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  scope :unprocessed, -> { where(processing_state: "pending") }
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  def parsed_content
    JSON.parse(content)
  end
  
  def processed?
    processing_state != "pending"
  end
  
  def failure?
    processing_state == "failure"
  end

  def success?
    processing_state == "success"
  end

  def pending?
    processing_state == "pending"
  end
  
  def self.required_initial_owner
    "0x00000000000000000000000000000000000face7"
  end
  
  def process!(persist:)
    if processed?
      raise "Ethscription already processed: #{inspect}"
    end
    
    begin
      unless initial_owner == self.class.required_initial_owner
        raise InvalidEthscriptionError.new("Invalid initial owner: #{initial_owner}")
      end
      
      if mimetype == ContractTransaction.transaction_mimetype
        build_contract_transaction(ethscription: self)
      elsif mimetype == SystemConfigVersion.system_mimetype
        version = SystemConfigVersion.create_from_ethscription!(self, persist: persist)
        
        assign_attributes(system_config_version: version)
      else
        raise InvalidEthscriptionError.new("Unexpected mimetype: #{mimetype}")
      end
      
      assign_attributes(
        processing_state: "success",
      )
    rescue InvalidEthscriptionError => e
      assign_attributes(
        processing_state: "failure",
        processing_error: e.message
      )
    end
    
    assign_attributes(processed_at: Time.current)
    
    update_columns(changes.transform_values(&:last)) if persist
    self
  end
  
  def self.valid_for_vm
    where(mimetype: valid_mimetypes).
    where(initial_owner: required_initial_owner)
  end
  
  def self.base_indexer_checksum
    last_imported = EthBlock.where(block_number: EthBlock.select("MAX(block_number)"))
    last_imported = last_imported.limit(1).first&.block_number
    
    return unless last_imported
    
    scope = Ethscription.
      valid_for_vm.
      where("block_number <= ?", last_imported).
      oldest_first
    
    subquery = scope.select(:transaction_hash)
    hash_value = Ethscription.from(subquery, :ethscriptions)
      .select("encode(digest(array_to_string(array_agg(transaction_hash), ''), 'sha256'), 'hex')
        as hash_value")
      .take
      .hash_value
  end
  
  def self.valid_mimetypes
    [
      ContractTransaction.transaction_mimetype,
      SystemConfigVersion.system_mimetype
    ]
  end
  
  def triggers_contract_interaction?
    mimetype == ContractTransaction.transaction_mimetype
  end
  
  def triggers_system_config_update?
    mimetype == SystemConfigVersion.system_mimetype
  end
  
  def valid_to?
    initial_owner == self.class.required_initial_owner
  end
  
  private
  
  def downcase_hex_fields
    self.transaction_hash = transaction_hash.downcase
    self.creator = creator.downcase
    self.initial_owner = initial_owner.downcase
  end
end