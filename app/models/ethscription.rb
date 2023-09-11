class Ethscription < ApplicationRecord
  has_many :contracts, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'
  has_one :contract_transaction_receipt, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'
  has_one :contract_transaction, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'
  has_many :contract_states, primary_key: 'ethscription_id', foreign_key: 'transaction_hash'

  after_create :process_contract_actions
  
  before_validation :downcase_hex_fields
  
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc) }
  scope :oldest_first, -> { order(block_number: :asc, transaction_index: :asc) }
  
  attr_accessor :mock_for_simulate_transaction

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
  
  def self.esc_findEthscriptionById(ethscription_id, as_of)
    resp = EthscriptionSync.findEthscriptionById(
      ethscription_id,
      as_of: as_of
    )
    
    ethscription_response_to_struct(resp)
  end
  
  private
  
  def process_contract_actions
    return unless ENV.fetch('ETHEREUM_NETWORK') == "eth-goerli" || Rails.env.development?
    
    ContractTransaction.on_ethscription_created(self)
  end
  
  def downcase_hex_fields
    self.ethscription_id = ethscription_id.downcase
    self.creator = creator.downcase
    self.current_owner = current_owner.downcase
    self.initial_owner = initial_owner.downcase
    self.previous_owner = previous_owner.downcase if previous_owner.present?
    self.content_sha = content_sha.downcase
  end
  
  def self.ethscription_response_to_struct(resp)
    params_to_type = {
      ethscriptionId: :ethscriptionId,
      blockNumber: :uint256,
      blockBlockhash: :string,
      transactionIndex: :uint256,
      creator: :address,
      currentOwner: :address,
      initialOwner: :address,
      creationTimestamp: :uint256,
      previousOwner: :address,
      contentUri: :string,
      contentSha: :string,
      mimetype: :string
    }
    
    str = Struct.new(*params_to_type.keys)
    
    resp.transform_keys!{|i| i.camelize(:lower).to_sym}
    resp = resp.symbolize_keys
    
    resp[:creationTimestamp] = Time.zone.parse(resp[:creationTimestamp]).to_i

    resp.each do |key, value|
      value_type = params_to_type[key]
      resp[key] = TypedVariable.create(value_type, value)
    end
    
    str.new(*resp.values_at(*params_to_type.keys))
  end
end