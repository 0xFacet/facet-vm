class Ethscription < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, touch: true, optional: true
  
  has_many :contracts, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'
  has_one :contract_transaction_receipt, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'
  has_one :contract_transaction, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'
  has_many :contract_states, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'

  before_validation :downcase_hex_fields
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  def process!
    if mimetype == ContractTransaction.transaction_mimetype
      ContractTransaction.create_from_ethscription!(self)
    elsif mimetype == ContractAllowListVersion.system_mimetype
      ContractAllowListVersion.create_from_ethscription!(self)
    else
      raise "Unexpected mimetype: #{mimetype}"
    end
  end
  
  private
  
  def downcase_hex_fields
    self.ethscription_id = ethscription_id.downcase
    self.creator = creator.downcase
    self.current_owner = current_owner.downcase
    self.initial_owner = initial_owner.downcase
    self.previous_owner = previous_owner.downcase if previous_owner.present?
    self.content_sha = content_sha.downcase
  end
end