class SystemConfigVersion < ApplicationRecord
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
  
  def self.create_from_ethscription!(eths)
    content = JSON.parse(eths.content)
    
    if eths.creator != PERMISSIONED_ADDRESS
      raise "Unexpected from: #{eths.from}"
    end
    
    if eths.initial_owner != "0x" + "0" * 40
      raise "Unexpected initial_owner: #{eths.initial_owner}"
    end
    
    if eths.mimetype != system_mimetype
      raise "Unexpected mimetype: #{eths.mimetype}"
    end
    
    if content['op'] != 'updateSupportedContracts'
      Rails.logger.info "Unexpected op: #{content['op']}"
      return
    end
    
    data = content['data']
    unless data.is_a?(Array) && data.all? { |el| el.to_s =~ /\A0x[a-f0-9]{64}\z/ }
      raise "Invalid data: #{data.inspect}"
    end
    
    create!(
      transaction_hash: eths.transaction_hash,
      block_number: eths.block_number,
      transaction_index: eths.transaction_index,
      supported_contracts: data.uniq
    )
  end
  
  def self.current_supported_contracts
    newest_first.first&.supported_contracts || []
  end
  
  def self.current_supported_contract_artifacts
    artifacts = Rails.cache.fetch([all]) do
      current_supported_contracts.map do |item|
        RubidityTranspiler.find_and_transpile(item)
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
end
