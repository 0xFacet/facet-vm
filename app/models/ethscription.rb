class Ethscription < ApplicationRecord
  has_many :contract_call_receipts, foreign_key: 'ethscription_id', dependent: :destroy
  has_many :contract_states, foreign_key: 'ethscription_id', dependent: :destroy
  has_many :contracts, primary_key: 'ethscription_id', foreign_key: 'contract_id',
            dependent: :destroy
            
  after_destroy :destroy_later_ethscriptions
  
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
end