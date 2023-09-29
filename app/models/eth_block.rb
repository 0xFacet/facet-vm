class EthBlock < ApplicationRecord
  has_many :ethscriptions, foreign_key: :block_number, primary_key: :block_number
  
  def import_ethscriptions(ethscriptions_data)
    sorted_ethscriptions_data = ethscriptions_data.sort_by do |ethscription_data|
      Integer(ethscription_data['transaction_index'])
    end
    
    sorted_ethscriptions_data.each do |ethscription_data|
      ethscriptions.create!(transform_server_response(ethscription_data))
    end
  end
  
  def transform_server_response(server_data)
    {
      ethscription_id: server_data['transaction_hash'],
      block_number: block_number,
      block_blockhash: blockhash,
      transaction_index: server_data['transaction_index'],
      creator: server_data['creator'],
      current_owner: server_data['current_owner'],
      initial_owner: server_data['initial_owner'],
      creation_timestamp: timestamp,
      previous_owner: server_data['previous_owner'],
      content_uri: server_data['content_uri'],
      content_sha: Digest::SHA256.hexdigest(server_data['content_uri']),
      mimetype: server_data['mimetype']
    }
  end  
end
