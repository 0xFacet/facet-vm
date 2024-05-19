class NewContractState < ApplicationRecord
  validates :contract_address, presence: true
  validates :key, presence: true
  validates :value, presence: true
  
  ARRAY_LENGTH_SUFFIX = "__length".freeze

  def self.load_state_as_hash(contract_address)
    results = where(contract_address: contract_address).pluck(:key, :value).to_h

    if ActiveRecord::Base.connection.adapter_name.downcase.include?('sqlite')
      results.transform_values! do |value|
        if value.is_a?(Float)
          if value == value.to_d.to_i.to_f
            value.to_d.to_i
          else
            raise "Unexpected float value in state: #{value}"
          end
        else
          value
        end
      end
    end
    
    results
  end
  
  def self.delete_state(contract_address:, keys_to_delete:)
    keys_to_delete = Array.wrap(keys_to_delete).map(&:to_json)
    return if keys_to_delete.empty?
    
    where(contract_address: contract_address).where("key IN (?)", keys_to_delete).delete_all
  end
  
  def self.import_records!(new_records)
    new_records = Array.wrap(new_records)
    return if new_records.empty?
    
    NewContractState.import!(new_records, on_duplicate_key_update: { conflict_target: [:contract_address, :key], columns: [:value] })
  end
  
  def self.build_structure(contract_address)
    as_hash = load_state_as_hash(contract_address)
    nested_structure = {}

    as_hash.each do |key, value|
      next if key.last == ARRAY_LENGTH_SUFFIX  # Skip array length keys

      keys = key
      current = nested_structure

      keys.each_with_index do |k, index|
        on_last_key = index == keys.length - 1
        on_second_to_last_key = index == keys.length - 2
        
        if on_last_key
          current[k] = value
        else
          next_key_is_array = as_hash.key?(keys[0..index] + [ARRAY_LENGTH_SUFFIX])
          
          current[k] ||= next_key_is_array ? [] : {}
          current = current[k]
        end
      end
    end

    convert_arrays(nested_structure)
  end

  def self.convert_arrays(structure)
    structure.each do |key, value|
      if value.is_a?(Hash) && value.keys.all? { |k| k.is_a?(Integer) }
        structure[key] = value.keys.sort.map { |i| value[i] }
      elsif value.is_a?(Hash)
        convert_arrays(value)
      end
    end
    structure
  end
end
