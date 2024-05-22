class StateManager
  attr_accessor :contract, :state_var_layout, :state_data, :max_indices,
  :transaction_changes, :block_changes, :saved_implementation,
  
  ARRAY_LENGTH_SUFFIX = "__length__".freeze
  
  def initialize(contract, state_var_layout, skip_state_save: false)
    @contract = contract
    @contract_address = contract.address
    @state_var_layout = state_var_layout

    @skip_state_save = skip_state_save
    
    reload_state
  end

  def reload_state
    @transaction_changes = {
      state: {}.with_indifferent_access,
    }.with_indifferent_access
    
    @block_changes = {
      state: {}.with_indifferent_access,
    }.with_indifferent_access
    
    @state_data = NewContractState.load_state_as_hash(@contract_address)
    
    contract.reload unless contract.new_record?

    @saved_implementation = {
      init_code_hash: contract.current_init_code_hash,
      type: contract.current_type
    }
  end
  
  def reverting_changes_if(read_only)
    old_read_only = @read_only_mode
    @read_only_mode = read_only
    yield
    @read_only_mode = old_read_only
  end
  
  def with_state_var_layout(layout)
    old_layout = @state_var_layout
    @state_var_layout = layout
    
    yield
    
    @state_var_layout = old_layout
  end
  
  def get_implementation
    if @transaction_changes[:implementation]
      return @transaction_changes[:implementation][:to]
    end
    
    if @block_changes[:implementation]
      return @block_changes[:implementation][:to]
    end
    
    @saved_implementation.with_indifferent_access
  end
  
  def set_implementation(**implementation)
    current = get_implementation
    
    @transaction_changes[:implementation] = {
      from: current,
      to: implementation
    }
    
    revert_if_read_only!
  end
  
  def revert_if_read_only!
    if @read_only_mode
      raise ContractErrors::InvalidStateVariableChange
    end
  end
  
  def get(*keys)
    type = validate_and_get_type(keys)
    validate_index_range(keys)
    
    value = raw_read(*keys)
    TypedVariable.create(type, value)
  end

  def format_key(keys)
    keys.as_json.map.with_index do |key, index|
      parent_type = index > 0 ? validate_and_get_type(keys[0..index-1]) : nil
      parent_type&.name == :mapping && key.is_a?(Integer) ? key.to_s : key
    end
  end
  
  def raw_read(*keys)
    key = format_key(keys)
  
    if @transaction_changes[:state].key?(key)
      return @transaction_changes[:state][key][:to]
    end
  
    value_at_start_of_tx(key)
  end
  
  def value_at_start_of_tx(key)
    key = format_key(key)
    
    if @block_changes[:state].key?(key)
      return @block_changes[:state][key][:to]
    end
    
    @state_data[key]
  end
  
  def set(*keys, typed_variable)
    unless typed_variable.is_a?(TypedVariable) || typed_variable.nil?
      raise TypeError, "Expected TypedVariable, got #{typed_variable.class}"
    end
    
    type = validate_and_get_type(keys)
    validate_type(type, typed_variable)
    validate_index_range(keys)
    json_key = format_key(keys)
    
    # TODO: adjust when we have nested arrays
    if typed_variable.is_a?(StructVariable)
      typed_variable.value.data.each do |field, field_value|
        field_type = type.struct_definition.fields[field]
        
        raw_write(keys + [field], value_to_write(field_value))
      end
    else
      raw_write(keys, value_to_write(typed_variable))
    end
  
    if @transaction_changes[:state].key?(json_key) && @transaction_changes[:state][json_key][:from] != @transaction_changes[:state][json_key][:to]
      revert_if_read_only!
    end
  end
  
  def value_to_write(value)
    if value.nil? || value.has_default_value?
      return nil 
    end
    
    value
  end
  
  def raw_write(keys, value)
    original_value = value_at_start_of_tx(keys)
    key = format_key(keys)
    json_value = value.as_json
    
    @transaction_changes[:state][key] = { from: original_value, to: json_value }
  end
  
  def commit_transaction
    apply_transaction
  end
  
  def apply_transaction
    @transaction_changes[:state].each do |key, change|
      next if change[:from] == change[:to]
      
      @block_changes[:state][key] ||= { from: @state_data[key], to: @state_data[key] }
      
      @block_changes[:state][key][:to] = change[:to]
    end

    if @transaction_changes[:implementation].present?
      @block_changes[:implementation] ||= { from: @saved_implementation, to: @saved_implementation }
      @block_changes[:implementation][:to] = @transaction_changes[:implementation][:to]
    end
    
    clear_transaction
  rescue => e
    binding.pry
  end
  
  def rollback_transaction
    clear_transaction
  end

  def start_transaction
    clear_transaction
  end
  
  # Clear transaction data
  def clear_transaction
    @transaction_changes = {
      state: {}.with_indifferent_access,
    }.with_indifferent_access
  end
  
  def persist(...)
    save_block_changes(...)
  end
  
  # Save block changes
  def save_block_changes(block_number)
    Contract.transaction do
      ContractBlockChangeLog.save_changes(@contract_address, block_number, @block_changes)

      new_records = @block_changes[:state].map do |key, change|
        next if change[:to].nil?
        {
          contract_address: @contract_address,
          key: key,
          value: change[:to]
        }
      end.compact
      
      NewContractState.import_records!(new_records)
      NewContractState.delete_state(contract_address: @contract_address, keys_to_delete: @block_changes[:state].select { |_, change| change[:to].nil? }.keys)
      
      if @block_changes[:implementation] && (@block_changes[:implementation][:from] != @block_changes[:implementation][:to])
        contract.update!(current_init_code_hash: @block_changes[:implementation][:to][:init_code_hash], current_type: @block_changes[:implementation][:to][:type])
        @saved_implementation = @block_changes[:implementation][:to]
      end
      
      @block_changes[:state].each do |key, change|
        if change[:to].nil?
          @state_data.delete(key)
        else
          @state_data[key] = change[:to]
        end
      end
      
      clear_block
      
      contract.touch unless contract.new_record?
    end
  rescue ActiveRecord::StaleObjectError => e
    reload_state
    
    raise ContractErrors::StaleContractError,
      "Contract state lock version mismatch. State has been reloaded."
  end
  
  def clear_block
    clear_transaction
    @block_changes = {
      state: {}.with_indifferent_access,
    }.with_indifferent_access
  end

  # Rollback to block
  def rollback_to_block(block_number)
    ContractBlockChangeLog.rollback_changes(@contract_address, block_number)
    reload_state
    @block_changes = {
      state: {}.with_indifferent_access,
    }.with_indifferent_access
  end

  def array_length(*keys)
    type = validate_and_get_type(keys)
    raise TypeError, "Not an array" unless type.name == :array

    if type.length
      return TypedVariable.create(:uint256, type.length)
    end
    
    length_key = keys + [ARRAY_LENGTH_SUFFIX]
    length_value = raw_read(*length_key) || 0
    TypedVariable.create(:uint256, length_value)
  end

  # Push to array
  def array_push(*keys, typed_variable)
    type = validate_and_get_type(keys)
    raise TypeError, "Not an array" unless type.name == :array
    raise IndexError, "Cannot push to fixed length array" if type.length

    length = array_length(*keys)
    raw_write((keys + [ARRAY_LENGTH_SUFFIX]), TypedVariable.create(:uint256, length.value + 1))
    set(*(keys + [length]), typed_variable)
    
    revert_if_read_only!
  end

  # Pop from array
  def array_pop(*keys)
    type = validate_and_get_type(keys)
    raise TypeError, "Not an array" unless type.name == :array
    raise IndexError, "Cannot pop from fixed length array" if type.length

    length = array_length(*keys).value
    raise "Array is empty" if length.zero?

    last_index = TypedVariable.create(:uint256, length - 1)
    value = get(*(keys + [last_index]))

    set(*(keys + [last_index]), nil)
    
    write_val = last_index.value == 0 ? nil : last_index
    raw_write((keys + [ARRAY_LENGTH_SUFFIX]), write_val)
    binding.pry if value.is_a?(Integer)
    revert_if_read_only!
    value
  end
  
  # end

  def validate_and_get_type(keys)
    layout = @state_var_layout
    keys.each_with_index do |segment, index|
      if layout.is_a?(Type)
        if layout.name == :mapping
          key_type = layout.key_type
          mapping_exception = segment.is_a?(TypedVariable) && segment.type.contract? && key_type.address?
          unless mapping_exception || TypedVariable.create_or_validate(key_type, segment)
            raise TypeError, "Invalid mapping key type at index #{index}: expected #{key_type.name}, got #{segment.class}"
          end
          layout = layout.value_type
        elsif layout.name == :array
          # unless (allow_untyped_array_index && segment.is_a?(Integer)) || (segment.is_a?(TypedVariable) && segment.type.is_uint?)
          unless TypedVariable.create_or_validate(:uint256, segment)
            # binding.pry
            raise TypeError, "Invalid array index type at index #{index}: expected Integer, got #{segment.class}"
          end
          
          layout = layout.value_type
        elsif layout.struct? # With struct .name is the name of the struct not the type
          unless layout.struct_definition.fields.key?(segment.to_s)
            # binding.pry
            raise KeyError, "Invalid struct field at segment #{index}: #{segment}"
          end
          layout = layout.struct_definition.fields[segment.to_s]
        else
          raise KeyError, "Invalid path at segment #{index}: #{keys.join('.')}"
        end
      elsif layout.is_a?(Hash) && layout.key?(segment.to_s)
        layout = layout[segment.to_s]
      else
        raise KeyError, "Invalid path: #{keys.as_json}"
      end
    end
    
    layout
  end  
  
  def container_of(keys)
    validate_and_get_type(keys[0..-2])
  end
  
  def validate_index_range(keys)
    container = container_of(keys)
    
    if container.is_a?(Type) && container.array?
      index = keys.last
      length = array_length(*keys[0..-2])
      if index.value >= length.value
        raise IndexError, "Index out of range for array"
      end
    end
  end
  
  def validate_type(expected_type, typed_variable)
    TypedVariable.create_or_validate(expected_type, typed_variable)
    # unless typed_variable.is_a?(TypedVariable) && typed_variable.type == expected_type
    #   raise TypeError, "Expected #{expected_type.name}, got #{typed_variable.type}"
    # end
  end
  
  def build_structure
    state_structure = build_structure_raw
    # binding.pry
    ensure_layout_defaults(@state_var_layout, state_structure)
    state_structure
  # rescue => e
  #   binding.pry
  end
  
  def build_structure_raw
    as_hash = state_data
    nested_structure = {}

    as_hash.each do |key, value|
      next if key.last == ARRAY_LENGTH_SUFFIX  # Skip array length keys

      keys = key
      current = nested_structure

      keys.each_with_index do |k, index|
        on_last_key = index == keys.length - 1
        on_second_to_last_key = index == keys.length - 2
        
        # begin
        #   container = validate_and_get_type(keys[0..index])
        # rescue KeyError, TypeError
        #   # Skip keys that are not in the current layout
        #   break
        # end
        
        if on_last_key
          current[k] = value
        else
          begin
            container = validate_and_get_type(keys[0..index])
            next_key_is_array = container.is_a?(Type) && container.array?
          rescue
            next_key_is_array = k.is_a?(Integer)
          end

          current[k] ||= next_key_is_array ? [] : {}
          current = current[k]
        end
      end
    end

    convert_arrays(nested_structure)
  end

  def convert_arrays(structure)
    structure.each do |key, value|
      if value.is_a?(Hash) && value.keys.all? { |k| k.is_a?(Integer) }
        structure[key] = value.keys.sort.map { |i| value[i] }
      elsif value.is_a?(Hash)
        convert_arrays(value)
      end
    end
    structure
  end


  private

  
  def ensure_layout_defaults(layout, structure, keys = [])
    layout.each do |key, type|
      current_keys = keys + [key]
  
      unless structure.key?(key)
        structure[key] = default_value_for_type(type)
      end
  
      if type.is_a?(Type)
        if type.mapping?
          structure[key] = {} unless structure[key].is_a?(Hash)
        elsif type.struct?
          structure[key] = {} unless structure[key].is_a?(Hash)
        elsif type.name == :array
          # TODO: arrays in mappings etc?
          structure[key] = [] unless structure[key].is_a?(Array)
          pad_array_with_defaults(structure[key], type, current_keys)
        end
      elsif type.is_a?(Hash)
        structure[key] ||= {}
        ensure_layout_defaults(type, structure[key], current_keys)
      end
    end
  end

  def pad_array_with_defaults(array, type, keys)
    array_length = array_length(*keys).value
    default_value = default_value_for_type(type.value_type)
    array_length.times do |i|
      array[i] ||= default_value
    end
  end
  
  def default_value_for_type(type)
    if type.is_a?(Type) && type.mapping? || type.struct?
      {}
    elsif type.is_a?(Type) && type.name == :array
      []
    else
      type.default_value
    end
  end
end
