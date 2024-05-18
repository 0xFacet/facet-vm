class StateManager
  attr_accessor :contract_address, :state_var_layout, :state_data, :max_indices,
  :transaction_changes, :block_changes, :on_change
  
  ARRAY_LENGTH_SUFFIX = "__length".freeze
  
  def initialize(contract_address, state_var_layout, on_change = nil, skip_state_save: false)
    @contract_address = contract_address
    @state_var_layout = state_var_layout
    @transaction_changes = {}
    @block_changes = {}
    @on_change = on_change
    @skip_state_save = skip_state_save
    
    reload_state
  end

  def reload_state
    @state_data = NewContractState.load_state_as_hash(@contract_address)
  end
  
  # Get value
  def get(*keys)
    type = validate_and_get_type(keys)
    validate_index_range(keys, type)
    # key = keys.as_json

    # if @transaction_changes.key?(key) && @transaction_changes[key][:to].nil?
    #   return TypedVariable.create(type)
    # end

    # if @block_changes.key?(key) && @block_changes[key][:to].nil?
    #   return TypedVariable.create(type)
    # end

    # value = @transaction_changes.dig(key, :to) || @block_changes.dig(key, :to) || @state_data[key]
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
    # key = keys.as_json
    key = format_key(keys)
    
    if @transaction_changes.key?(key) && @transaction_changes[key][:to].nil?
      return nil
    end
    
    if @block_changes.key?(key) && @block_changes[key][:to].nil?
      return nil
    end

    @transaction_changes.dig(key, :to) || @block_changes.dig(key, :to) || @state_data[key]
  end
  
  # Set value
  def set(*keys, typed_variable)
    type = validate_and_get_type(keys)
    validate_type(type, typed_variable)
    validate_index_range(keys, type)
    json_key = format_key(keys)
    
    # current_value = get(*keys).value

    # @transaction_changes[key] = { from: current_value, to: typed_variable.value }
    
    container = container_of(keys)
    
    array_container = container.is_a?(TypedVariable) && container.array?
    
    if typed_variable.value == type.default_value && !array_container
      # @transaction_changes[key][:to] = nil
      set_transaction_change_value(keys, nil, container)
    else
      set_transaction_change_value(keys, typed_variable, container)
    end
    
    if @transaction_changes.key?(json_key) && @transaction_changes[json_key][:from] != @transaction_changes[json_key][:to]
      @on_change&.call
    end
  end
  
  def set_transaction_change_value(key, value, container)
    current_value = raw_read(*key)
    # json_key = key.as_json
    json_key = format_key(key)
    # unless container.is_a?(TypedVariable) && container.array?
    #   json_key[-1] = json_key[-1].to_s
    # end
    
    json_value = value.as_json
    
    @transaction_changes[json_key] = { from: current_value, to: json_value }
  end
  
  def raw_write(*keys, value, container)
    # json_key = keys.as_json
    json_key = format_key(keys)
    # unless container.is_a?(TypedVariable) && container.array?
    #   json_key[-1] = json_key[-1].to_s# if json_key.is_a?(Array) && json_key.last.is_a?(Integer)
    # end
    
    json_value = value.as_json
    @transaction_changes[json_key] = { from: raw_read(*keys), to: json_value }
    @on_change&.call if @transaction_changes[json_key][:from] != @transaction_changes[json_key][:to]
  end
  
  def commit_transaction
    apply_transaction
  end
  
  def apply_transaction
    @transaction_changes.each do |key, change|
      next if change[:from] == change[:to]
      
      @block_changes[key] ||= { from: @state_data[key], to: @state_data[key] }
      
      @block_changes[key][:to] = change[:to]
    end

    clear_transaction
  rescue
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
    @transaction_changes = {}
  end
  
  def changes_in_block
    @block_changes.select { |_, change| change[:from] != change[:to] }
  end
  
  def persist(...)
    save_block_changes(...)
  end
  
  # Save block changes
  def save_block_changes(block_number)
    ContractBlockChangeLog.save_changes(@contract_address, block_number, changes_in_block)

    new_records = @block_changes.map do |key, change|
      next if change[:to].nil?
      {
        contract_address: @contract_address,
        key: key,
        value: change[:to]
      }
    end.compact
    
    NewContractState.import_records!(new_records)
    NewContractState.delete_state(contract_address: @contract_address, keys_to_delete: @block_changes.select { |_, change| change[:to].nil? }.keys)
    
    @block_changes.each do |key, change|
      if change[:to].nil?
        @state_data.delete(key)
      else
        @state_data[key] = change[:to]
      end
    end
    
    structure = build_structure
    contract = Contract.find_by_address(@contract_address)
    
    if contract.current_state != structure
      contract.update!(current_state: structure)
    
      state = ContractState.find_or_initialize_by(
        contract_address: @contract_address,
        block_number: block_number
      )
      
      state.type ||= contract.current_type
      state.init_code_hash ||= contract.current_init_code_hash
      state.state = structure
      
      state.save! unless @skip_state_save
    end
    
    clear_block
  end
  
  def clear_block
    clear_transaction
    @block_changes = {}
  end

  # Rollback to block
  def rollback_to_block(block_number)
    ContractBlockChangeLog.rollback_changes(@contract_address, block_number)
    reload_state
    @block_changes = {}
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
    set(*(keys + [length]), typed_variable)
    raw_write(*(keys + [ARRAY_LENGTH_SUFFIX]), TypedVariable.create(:uint256, length.value + 1), type)
  # rescue => e
  #   binding.pry
  end

  # Pop from array
  def array_pop(*keys)
    type = validate_and_get_type(keys)
    raise TypeError, "Not an array" unless type.name == :array
    raise IndexError, "Cannot pop from fixed length array" if type.length

    length = array_length(*keys).value
    raise "Array is empty" if length.zero?

    last_index = length - 1
    value = get(*(keys + [TypedVariable.create(:uint256, last_index)]))

    set_transaction_change_value(keys + [last_index], nil, type)
    raw_write(*(keys + [ARRAY_LENGTH_SUFFIX]), TypedVariable.create(:uint256, last_index), type)
    value
  end
  
  
  # Get array length
  # def array_length(*keys)
  #   type = validate_and_get_type(keys)
  #   array_key = keys

  #   raise TypeError, "Not an array" unless type.name == :array
    
  #   keys_prefix = keys.as_json
    
  #   len = if type.length
  #     type.length
  #   else
  #     max_index = @state_data.keys.select { |key| key[0, keys_prefix.size] == keys_prefix }
  #                                   .map { |key| key[keys_prefix.size] }
  #                                   .select { |idx| idx.is_a?(Integer) }
  #                                   .max
  #     max_index ? max_index + 1 : 0
  #   end
    
  #   TypedVariable.create(:uint256, len)
  # rescue => e
  #   binding.pry
  # end
  
  # def get_max_index(keys)
  #   @max_indices[keys.as_json].as_json
  # end

  # Push to array
  # def array_push(*keys, typed_variable)
  #   type = validate_and_get_type(keys)
    
  #   raise TypeError, "Not an array" unless type.name == :array
    
  #   if type.length
  #     raise IndexError, "Cannot push to fixed length array"
  #   end

  #   array_key = keys
  #   length = array_length(*keys)
  #   # length = TypedVariable.create(:uint256, array_length(*keys))
  #   set(*(keys + [length]), typed_variable)
  #   # set_max_index(array_key, length)
  # end

  # # Pop from array
  # def array_pop(*keys)
  #   type = validate_and_get_type(keys)
    
  #   raise TypeError, "Not an array" unless type.name == :array
    
  #   if type.length
  #     raise IndexError, "Cannot pop from fixed length array"
  #   end
    
  #   array_key = keys
  #   length = array_length(*keys).as_json
  #   raise "Array is empty" if length.zero?

  #   last_index = TypedVariable.create(:uint256, length - 1)
  #   current_value = get(*(keys + [last_index]))
  #   key = (keys + [last_index])
    
  #   # @transaction_changes[key] = { from: current_value, to: nil }
  #   @on_change&.call
  #   set_transaction_change_value(key, nil)
    
  #   # set_max_index(array_key, last_index.value - 1) if last_index.value > 0
  #   current_value
  # end
  
  # def set_max_index(keys, index)
  #   @max_indices[keys.as_json] = index
  # end
  
  def detecting_changes(revert_on_change:)
    old_on_change = on_change
    
    self.on_change = lambda do
      if revert_on_change
        raise ContractErrors::InvalidStateVariableChange.new
      end
    end
    
    yield
    
    self.on_change = old_on_change
  end

  # def validate_and_get_type(keys)
  #   type_object = @state_var_layout
  #   keys.each_with_index do |key, index|
  #     if type_object.is_a?(Hash) && type_object.key?(key.to_s)
  #       type_object = type_object[key.to_s]
  #     elsif type_object.name == :mapping
  #       key_type = type_object.key_type
        
  #       mapping_exception = key.is_a?(TypedVariable) && key.type.contract? && key_type.address?
  #       unless (key.is_a?(TypedVariable) && key.type == key_type) || mapping_exception
  #         raise TypeError, "Invalid mapping key type at index #{index}"
  #       end
        
  #       type_object = type_object.value_type
  #     elsif type_object.name == :array
  #       raise TypeError, "Invalid array index type at index #{index}" unless key.is_a?(Integer)
  #       type_object = type_object.value_type
  #     else
  #       raise KeyError, "Invalid path: #{keys.join('.')}"
  #     end
  #   end
  #   type_object
  # rescue => e
  #   binding.pry
  # end
  
  def validate_and_get_type(keys)
    layout = @state_var_layout

    keys.each_with_index do |segment, index|
      if layout.is_a?(Type)
        if layout.name == :mapping
          key_type = layout.key_type
          
          mapping_exception = segment.is_a?(TypedVariable) && segment.type.contract? && key_type.address?
          # unless (segment.is_a?(TypedVariable) && segment.type == key_type) || mapping_exception
          unless mapping_exception || TypedVariable.create_or_validate(key_type, segment)
            binding.pry
            raise TypeError, "Invalid mapping key type at index #{index}: expected #{key_type.name}, got #{segment.class}"
          end

          layout = layout.value_type
        elsif layout.name == :array
          # unless segment.is_a?(Integer)
          unless segment.type.is_uint?
            binding.pry
            raise TypeError, "Invalid array index type at index #{index}: expected Integer, got #{segment.class}"
          end
          layout = layout.value_type
        else
          raise KeyError, "Invalid path at segment #{index}: #{keys.join('.')}"
        end
      elsif layout.is_a?(Hash) && layout.key?(segment.to_s)
        layout = layout[segment.to_s]
      else
        raise KeyError, "Invalid path: #{keys.join('.')}"
      end
    end

    layout
  # rescue => e
  #   binding.pry
  end
  
  def container_of(keys)
    validate_and_get_type(keys[0..-2])
  end
  
  def validate_index_range(keys, type)
    if type.name == :array
      index = keys.last
      length = array_length(*keys[0..-2])
      if index >= length
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
    state_structure = NewContractState.build_structure(@contract_address)
    ensure_layout_defaults(@state_var_layout, state_structure)
    state_structure
  end


  private

  def ensure_layout_defaults(layout, structure)
    layout.each do |key, type|
      unless structure.key?(key)
        structure[key] = default_value_for_type(type)
      end

      if type.is_a?(Type) && type.name == :mapping
        structure[key] = {} unless structure[key].is_a?(Hash)
      elsif type.is_a?(Type) && type.name == :array
        structure[key] = [] unless structure[key].is_a?(Array)
      end

      if type.is_a?(Hash)
        structure[key] ||= {}
        ensure_layout_defaults(type, structure[key])
      elsif type.is_a?(Type) && type.name == :mapping
        structure[key] ||= {}
      elsif type.is_a?(Type) && type.name == :array
        structure[key] ||= []
      end
    end
  end

  def default_value_for_type(type)
    if type.is_a?(Type) && type.name == :mapping
      {}
    elsif type.is_a?(Type) && type.name == :array
      []
    else
      type.default_value
    end
  end
end
