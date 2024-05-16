class JsonbWrapper
  attr_accessor :state_var_layout, :on_change, :contract, :block_data

  def initialize(state_var_layout, on_change, contract)
    @state_var_layout = state_var_layout
    @on_change = on_change
    @contract = contract # ActiveRecord object that has a jsonb column current_state

    # state_data = JSON.parse(contract.attributes_before_type_cast['current_state'] || "{}")
    # Benchmark.msr do
      @block_data = JsonState.new(contract.current_state, contract.address)
    # end
    # ap @block_data
    @dirty_stack = []
  end

  def detecting_changes(revert_on_change:)
    old_on_change = on_change
    # binding.pry if revert_on_change
    self.on_change = ->(path, value) do
      if revert_on_change
        raise ContractErrors::InvalidStateVariableChange.new
      end
    end
    # ap "YIELD"
    yield
    
    self.on_change = old_on_change
  end
  
  def start_transaction
    @block_data.clear_transaction
  end

  def commit_transaction
    @block_data.apply_transaction
  end

  def rollback_transaction
    @block_data.rollback_transaction
  end

  def read(*path)
    path = ::VM.deep_unbox(path)
    path = path.as_json
    # ap path
    validate_path!(*path)
    type_object = layout_for_path(*path)

    container_type = layout_for_path(*path[0..-2])

    if container_type.is_a?(Type) && container_type.name == :array
      array_index = path.pop
      array_type = container_type

      unless array_index.is_a?(Integer)
        raise ArgumentError, "Array index must be an Integer"
      end

      if array_type.length && array_index >= array_type.length
        raise IndexError, "Index out of range for fixed-length array"
      end

      result = @block_data.get(*path)

      if result.is_a?(Array)
        if array_index < result.length
          value = result[array_index]
        else
          value = nil
        end
      else
        result = []
      end

      if value.nil?
        if array_type.length && array_index < array_type.length
          value = TypedVariable.create(array_type.value_type)
        else
          raise IndexError, "Index out of range for variable-length array"
        end
      else
        value = TypedVariable.create(array_type.value_type, value)
      end
    else
      result = @block_data.get(*path)
      value = type_output(type_object, result, path)
    end

    value
  # rescue => e
  #   binding.pry
  end
  
  def type_output(type_object, result, path)
    if [:array, :mapping].exclude?(type_object.name)
      TypedVariable.create(type_object, result)
    else
      ProxyBase.new(self, *path, memory_var: TypedVariable.create(type_object, result))
    end
  end

  def write(*path, value)
    path = ::VM.deep_unbox(path)
    value = ::VM.deep_unbox(value)
    # binding.pry if value.is_a?(ArrayVariable)
    path = path.as_json
    # value = value.as_json
    
    validate_path!(*path)
    container_type = layout_for_path(*path[0..-2])

    if container_type.is_a?(Type) && container_type.name == :array
      array_index = path.pop
      array_type = container_type

      unless array_index.is_a?(Integer)
        raise ArgumentError, "Array index must be an Integer"
      end

      path.push(array_index)
      
      if array_type.length && array_index >= array_type.length
        raise IndexError, "Index out of range for fixed-length array"
      end

      result = @block_data.get(*path[0..-2])
      if result.nil?
        result = []
        @block_data.set(*path[0..-2], result)
      end

      if result.is_a?(Array)
        current_value = TypedVariable.create(array_type.value_type, result[array_index])
        # current_value = result[array_index]
        
        if value.nil? && array_index == result.length - 1
          @block_data.set(*path[0..-2], result.reverse.drop(1).reverse)
          @on_change.call(path, value) if @on_change
          return
        end
        
        unless current_value.eq(value).value
          @block_data.set(*path, value.as_json)
          @on_change.call(path, value) if @on_change
        end
      else
        raise TypeError, "Expected an Array at #{path[0..-2].join('.')}, but found #{result.class}"
      end

    else
      current_value = read(*path)
      # current_value = @block_data.get(*path)
      # unless current_value == value
      unless current_value.eq(value).value
        # Compare variables directly but can't now bc of coercing contract variables to addresses
        if value.as_json == TypedVariable.create(layout_for_path(*path)).as_json
          @block_data.set(*path, nil)
        else
          @block_data.set(*path, value.as_json)
        end
        # binding.pry if path[0] == 'balanceOf'
        @on_change.call(path, value) if @on_change
      end
    end
  # rescue => e
  #   binding.pry
  end
  
  def default_value_for_type(type)
    case type.name
    when :mapping
      {}
    when :array
      []
    else
      type.default_value
    end
  end
  
  def persist(block_number)
    changes = @block_data.changes
    return if changes.empty?
    
    # logs = @block_data.build_block_changes(block_number)
    # binding.pry
    # Save block changes before applying changes
    @block_data.save_block_changes(block_number)
    # @block_data.change_log = {}
    
    @state_var_layout.each do |key, type|
      unless @block_data.state_data.key?(key)
        @block_data.state_data[key] = default_value_for_type(type)
      end
    end

    contract.update!(current_state: @block_data.state_data)
    
    return# logs
    
    # Build a single JSON object with all updates
    update_json = changes.each_with_object({}) do |(path, change), acc|
      current = acc
      path.each_with_index do |segment, idx|
        segment_key = segment.is_a?(Integer) ? segment : segment.to_s
        if idx == path.length - 1
          current_value = @block_data.get(*path)
          current[segment_key] = current_value
        else
          current[segment_key] ||= {}
          current = current[segment_key]
        end
      end
    end
    ap changes
ap update_json
    # Perform incremental update using PostgreSQL JSONB functions
    set_operations = build_jsonb_set_operations(update_json)
    ap set_operations
    sql = ActiveRecord::Base.send(:sanitize_sql_array, ["UPDATE #{contract.class.table_name} SET current_state = #{set_operations} WHERE id = ?", contract.id])
    ActiveRecord::Base.connection.execute(sql)
  end

  def rollback_to_block(block_number)
    @block_data.rollback_to_block(block_number)
    
    contract.update!(current_state: @block_data.state_data)
    
    return
    # Persist the reverted state without creating a new change log
    update_json = @block_data.state_data


    # Construct a single JSONB set operation to apply all changes
    set_operations = build_jsonb_set_operations(update_json)

    # Perform a single incremental update using PostgreSQL JSONB functions
    sql = "UPDATE #{contract.class.table_name} SET current_state = #{set_operations} WHERE id = #{contract.id}"
    ActiveRecord::Base.connection.execute(sql)
  end

  private

  def validate_path!(*path)
    layout = @state_var_layout

    path.each_with_index do |segment, index|
      if layout.is_a?(Type)
        if layout.name == :mapping
          layout = layout.value_type
        elsif layout.name == :array
          if segment.is_a?(Integer)
            layout = layout.value_type
          else
            # binding.pry
            raise ArgumentError, "Index mismatch at segment #{index + 1}: expected Integer, got #{segment.class}"
          end
        elsif layout.key_type && layout.value_type
          if segment.is_a?(TypedVariable) && segment.type == layout.key_type.name
            layout = layout.value_type
          else
            raise ArgumentError, "Type mismatch at segment #{index + 1}: expected #{layout.key_type.name}, got #{segment.type}"
          end
        else
          raise ArgumentError, "Invalid path: #{path[0..index].join('.')}"
        end
      elsif layout.is_a?(Hash) && layout.key?(segment.to_s)
        layout = layout[segment.to_s]
      else
        raise ArgumentError, "Invalid path: #{path[0..index].join('.')}"
      end
    end

    unless layout.is_a?(Type)
      raise ArgumentError, "Invalid path: #{path.join('.')}"
    end
  end

  def layout_for_path(*path)
    layout = @state_var_layout

    path.each do |segment|
      if layout.is_a?(Type)
        if layout.name == :mapping
          layout = layout.value_type
        elsif layout.name == :array
          if segment.is_a?(Integer)
            layout = layout.value_type
          else
            raise ArgumentError, "Index mismatch: expected Integer, got #{segment.class}"
          end
        end
      elsif layout.is_a?(Hash) && layout.key?(segment.to_s)
        layout = layout[segment.to_s]
      else
        raise ArgumentError, "Invalid path: #{path.join('.')}"
      end
    end

    layout
  end

  def default_value(*path)
    type_object = layout_for_path(*path)
    TypedVariable.create(type_object)
  end

  def build_jsonb_set_operations(update_json, prefix = 'current_state')
    update_json.reduce(prefix) do |operations, (key, value)|
      jsonb_path = key.split('.').map { |k| ActiveRecord::Base.connection.quote_string(k) }.join(',')

      # jsonb_path = json_path_for(key)
      # value_json = value.is_a?(Hash) ? value.to_json : value.to_json
      
      value_json = ActiveRecord::Base.connection.quote(value.to_json)

      
      "jsonb_set(#{operations}, '{#{jsonb_path}}'::text[], #{value_json}::jsonb)"
    end
  end

  # def json_path_for(key)
  #   key.split('.').map { |k| "\"#{k}\"" }.join(',')
  # end
end
