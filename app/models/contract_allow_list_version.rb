class ContractAllowListVersion < ApplicationRecord
  belongs_to :ethscription,
  primary_key: 'ethscription_id', foreign_key: 'transaction_hash',
  touch: true, optional: true
  
  scope :newest_first, -> {
    order(block_number: :desc, transaction_index: :desc) 
  }
  
  def self.create_from_ethscription!(eths)
    content = JSON.parse(eths.content)
    
    if eths.mimetype != "application/vnd.facet.system+json"
      raise "Unexpected mimetype: #{eths.mimetype}"
    end
    
    if content['op'] != 'updateContractAllowList'
      raise "Unexpected op: #{content['op']}"
    end
    
    data = content['data']
    unless data.is_a?(Array) && data.all? { |element| element.is_a?(String) }
      raise "Invalid data: #{data.inspect}"
    end
    
    create!(
      ethscription_id: eths.ethscription_id,
      block_number: eths.block_number,
      transaction_index: eths.transaction_index,
      allow_list: data.uniq
    )
  end
  
  def self.current_list
    newest_first.first&.allow_list || []
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :allow_list,
          :block_number,
          :transaction_index,
        ]
      )
    )
  end
end
