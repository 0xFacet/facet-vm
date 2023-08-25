class Ethscription < ApplicationRecord
  has_one :contract_call_receipt, primary_key: 'ethscription_id', dependent: :destroy
  has_many :contract_states, primary_key: 'ethscription_id', dependent: :destroy
  has_many :contracts, primary_key: 'ethscription_id', foreign_key: 'contract_id',
            dependent: :destroy
            
  after_create :process_contract_actions
  
  before_validation :downcase_hex_fields
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }

  def later_ethscriptions
    Ethscription.where(
      'block_number > :block_number OR ' +
      '(block_number = :block_number AND transaction_index > :transaction_index)',
      block_number: block_number, 
      transaction_index: transaction_index
    )
  end
  
  def delete_with_later_ethscriptions
    Ethscription.transaction do
      delete
      later_ethscriptions.delete_all
    end
  end
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  private
  
  def process_contract_actions
    return unless ENV['ETHEREUM_NETWORK'] == "eth-goerli" || Rails.env.development?
    
    ContractTransaction.create_and_execute_from_ethscription_if_needed(self)
  end
  
  def downcase_hex_fields
    self.ethscription_id = ethscription_id.downcase
    self.creator = creator.downcase
    self.current_owner = current_owner.downcase
    self.initial_owner = initial_owner.downcase
    self.previous_owner = previous_owner.downcase if previous_owner.present?
    self.content_sha = content_sha.downcase
  end
end