class StateAttestation < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  
  has_many :ethscriptions, primary_key: :block_number, foreign_key: :block_number
  has_many :contracts, primary_key: :block_number, foreign_key: :block_number
  has_many :transaction_receipts, primary_key: :block_number, foreign_key: :block_number
  has_many :contract_transactions, primary_key: :block_number, foreign_key: :block_number
  has_many :system_config_versions, primary_key: :block_number, foreign_key: :block_number
  has_many :contract_states, primary_key: :block_number, foreign_key: :block_number
  has_many :contract_artifacts, primary_key: :block_number, foreign_key: :block_number
  has_many :contract_calls, primary_key: :block_number, foreign_key: :block_number
  
  def self.create_next_attestations!(batch_size)
    batch_size.times do |i|
      create_next_attestation!
    end
  end
  
  def self.create_next_attestation!
    StateAttestation.transaction do
      next_block_number = if StateAttestation.exists?
        StateAttestation.maximum(:block_number) + 1
      else
        EthBlock.processed.minimum(:block_number)
      end
      
      locked_next_block = EthBlock.where(block_number: next_block_number)
        .lock("FOR UPDATE SKIP LOCKED")
        .first
      
      return unless locked_next_block&.processed?
        
      create_for_block!(locked_next_block.block_number)
    end
  end
  
  def self.create_for_block!(block_number)
    prev_attestation = StateAttestation.find_by(block_number: block_number - 1)
    
    record = new(
      parent_state_hash: prev_attestation&.parent_state_hash,
      block_number: block_number
    )
    
    record.generate_attestation_hash
    record.save!
  end
  
  def generate_attestation_hash
    hash = Digest::SHA256.new
    hash << (parent_state_hash || "NULL")
  
    associations_to_hash.each do |association|
      hashable_attributes = quoted_hashable_attributes(association.klass)
      records = association_scope(association).pluck(*hashable_attributes)
      
      records.map! { |record| record.nil? ? 'NULL' : record }
      hash << records.join
    end
  
    self.state_hash = "0x" + hash.hexdigest
  end
  
  def association_scope(association)
    association.klass.oldest_first.where(block_number: block_number)
  end
  
  def associations_to_hash
    self.class.reflect_on_all_associations(:has_many) +
    [self.class.reflect_on_association(:eth_block)]
  end
  
  def hashable_attributes(klass)
    klass.columns_hash.reject do |k, v|
      v.type == :datetime || ['id', 'runtime_ms'].include?(k)
    end.keys.sort
  end
  
  def quoted_hashable_attributes(klass)
    hashable_attributes(klass).map do |attr|
      "md5(#{klass.connection.quote_column_name(attr)}::text)"
    end
  end
end
