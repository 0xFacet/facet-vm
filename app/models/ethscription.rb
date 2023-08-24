class Ethscription < ApplicationRecord
  has_one :contract_call_receipt, primary_key: 'ethscription_id', dependent: :destroy
  has_many :contract_states, primary_key: 'ethscription_id', dependent: :destroy
  has_many :contracts, primary_key: 'ethscription_id', foreign_key: 'contract_id',
            dependent: :destroy
            
  after_create :process_contract_actions
  
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
    later_ethscriptions.or(where(id: id)).delete_all
  end
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  private
  
  def process_contract_actions
    return unless ENV['ETHEREUM_NETWORK'] == "eth-goerli" || Rails.env.development?
    
    ContractTransaction.create_and_execute_from_ethscription_if_needed(self)
  end
end