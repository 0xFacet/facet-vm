class ContractAllowListVersion < ApplicationRecord
  belongs_to :ethscription,
  primary_key: 'ethscription_id', foreign_key: 'transaction_hash',
  touch: true, optional: true
  
  # TODO: permissioned address
  
  scope :newest_first, -> {
    order(block_number: :desc, transaction_index: :desc) 
  }
  
  def self.system_mimetype
    "application/vnd.facet.system+json"
  end
  
  def self.create_from_ethscription!(eths)
    ContractAllowListVersion.transaction do
      if eths.contract_actions_processed_at.present?
        raise "ContractTransaction already created for #{eths.inspect}"
      end
      
      content = JSON.parse(eths.content)
      
      if eths.initial_owner != "0x" + "0" * 40
        raise "Unexpected initial_owner: #{eths.initial_owner}"
      end
      
      if eths.mimetype != system_mimetype
        raise "Unexpected mimetype: #{eths.mimetype}"
      end
      
      if content['op'] != 'updateContractAllowList'
        raise "Unexpected op: #{content['op']}"
      end
      
      data = content['data']
      unless data.is_a?(Array) && data.all? { |el| el.to_s =~ /\A0x[a-f0-9]{64}\z/ }
        raise "Invalid data: #{data.inspect}"
      end
      
      create!(
        transaction_hash: eths.ethscription_id,
        block_number: eths.block_number,
        transaction_index: eths.transaction_index,
        allow_list: data.uniq
      )
      
      end_time = Time.current
      
      eths.update_columns(
        contract_actions_processed_at: end_time,
        updated_at: end_time
      )
    end
  end
  
  def self.current_list
    newest_first.first&.allow_list || []
  end
  
  def self.current_artifacts
    current_list.map do |item|
      RubidityTranspiler.find_and_transpile(item)
    end
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
