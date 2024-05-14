class JsonState
  attr_reader :state_data, :transaction_data, :change_log

  def initialize(state_data, contract_address)
    @state_data = state_data
    @transaction_data = {}
    @change_log = {}
    @contract_address = contract_address
  end

  def get(*keys)
    value = keys.reduce(@transaction_data) { |data, key| data.is_a?(Hash) ? data[key.to_s] : data[key] if data } ||
            keys.reduce(@state_data) { |data, key| data.is_a?(Hash) ? data[key.to_s] : data[key] if data }
    value
  end

  def set(*keys, value)
    last_key = keys.pop

    # Ensure the target path exists in transaction_data, using state_data if needed
    target = keys.reduce(@transaction_data) do |data, key|
      key = key.to_s if data.is_a?(Hash)
      data[key] ||= deep_dup(@state_data[key.to_s] || {})
    end

    if target.is_a?(Array)
      target[last_key.to_i] = value
    elsif target.is_a?(Hash)
      target[last_key.to_s] = value
    else
      raise TypeError, "Unexpected target type: #{target.class}"
    end

    log_change(keys + [last_key], value)
  end

  def apply_transaction
    traverse_and_apply(@transaction_data, [])
    clear_transaction
  end

  def rollback_transaction
    clear_transaction
  end

  def clear_transaction
    @transaction_data = {}
  end

  def changes
    @change_log
  end

  def save_block_changes(block_number)
    serialized_changes = @change_log.to_json
    ActiveRecord::Base.connection.execute(
      "INSERT INTO contract_block_change_logs (block_number, contract_address, state_changes) VALUES (#{block_number}, '#{@contract_address}', '#{serialized_changes}'::jsonb)"
    )
    @change_log = {}
  end

  def rollback_to_block(block_number)
    result = ActiveRecord::Base.connection.execute(
      "SELECT state_changes FROM contract_block_change_logs WHERE block_number > #{block_number} AND contract_address = '#{@contract_address}' ORDER BY block_number DESC"
    )

    result.each do |row|
      changes = JSON.parse(row['state_changes'])
      changes.each do |keys_string, change|
        keys = JSON.parse(keys_string)
        revert_change(keys, change['old_value'])
      end
    end

    # Clean up the change logs beyond the rollback point
    ActiveRecord::Base.connection.execute(
      "DELETE FROM contract_block_change_logs WHERE block_number > #{block_number} AND contract_address = '#{@contract_address}'"
    )
  end

  private

  def traverse_and_apply(data, keys)
    data.each do |key, value|
      new_keys = keys + [key]
      if value.is_a?(Hash)
        traverse_and_apply(value, new_keys)
      else
        update_state_and_log(new_keys, value)
      end
    end
  end

  def update_state_and_log(keys, new_value)
    current = @state_data
    
    keys[0...-1].each do |key|
      key = key.to_s if current.is_a?(Hash)
      current = current[key] ||= {}
    end
    
    last_key = keys.last
    last_key = last_key.to_s if current.is_a?(Hash)

    original_value = current[last_key]
    current[last_key] = new_value

    unless @change_log.key?(keys)
      @change_log[keys] = { old_value: original_value, new_value: new_value }
    end

    @change_log.delete_if { |_, change| change[:old_value] == change[:new_value] }
  end

  def revert_change(keys, old_value)
    current = @state_data
    keys[0...-1].each do |key|
      key = key.to_s if current.is_a?(Hash)
      current = current[key] ||= {}
    end
    last_key = keys.last
    last_key = last_key.to_s if current.is_a?(Hash)
    current[last_key] = old_value
    
    if current.is_a?(Array)
      while current.last.nil? && current.length > 0
        current.pop
      end
    end
  end

  def log_change(keys, new_value)
    current = @state_data
    keys[0...-1].each do |key|
      key = key.to_s if current.is_a?(Hash)
      current = current[key] ||= {}
    end
    last_key = keys.last
    last_key = last_key.to_s if current.is_a?(Hash)
    
    original_value = current[last_key.as_json]
    @change_log[keys] = { old_value: original_value, new_value: new_value } unless @change_log.key?(keys)
    
    @change_log.delete_if { |_, change| change[:old_value] == change[:new_value] }
  end

  def deep_dup(obj)
    case obj
    when Array
      obj.map { |e| deep_dup(e) }
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
    else
      obj
    end
  end
end
