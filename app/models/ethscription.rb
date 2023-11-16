class Ethscription < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, touch: true, optional: true
  
  has_many :contracts, primary_key: 'transaction_hash', foreign_key: 'transaction_hash'
  has_one :transaction_receipt, primary_key: 'transaction_hash', foreign_key: 'transaction_hash'
  has_one :contract_transaction, primary_key: 'transaction_hash', foreign_key: 'transaction_hash'
  has_many :contract_states, primary_key: 'transaction_hash', foreign_key: 'transaction_hash'

  before_validation :downcase_hex_fields
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  def process!
    ContractAllowListVersion.transaction do
      if contract_actions_processed_at.present?
        raise "ContractTransaction already created for #{eths.inspect}"
      end
      
      if mimetype == ContractTransaction.transaction_mimetype
        ContractTransaction.create_from_ethscription!(self)
      elsif mimetype == ContractAllowListVersion.system_mimetype
        ContractAllowListVersion.create_from_ethscription!(self)
      else
        raise "Unexpected mimetype: #{mimetype}"
      end
      
      end_time = Time.current
        
      update_columns(
        contract_actions_processed_at: end_time,
        updated_at: end_time
      )
    end
  end
  
  private
  
  def downcase_hex_fields
    self.transaction_hash = transaction_hash.downcase
    self.creator = creator.downcase
    self.initial_owner = initial_owner.downcase
  end
end