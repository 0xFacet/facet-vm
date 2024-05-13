require 'json'

class JsonbWrapper
  attr_accessor :state_var_layout, :on_change, :contract, :block_data

  def initialize(state_var_layout, on_change, contract)
    @state_var_layout = state_var_layout
    @on_change = on_change
    @contract = contract # ActiveRecord object that has a jsonb column current_state

    # Load and parse the JSON blob from the database
    result = ActiveRecord::Base.connection.execute("SELECT current_state FROM #{contract.class.table_name} WHERE id = #{contract.id}")
    json_blob = result.getvalue(0, 0)
    state_data = JSON.parse(json_blob)

    @block_data = JsonState.new(state_data, contract.address)
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
    validate_path!(*path)
    result = @block_data.get(*path)
    type_object = layout_for_path(*path)
    value = if result
              TypedVariable.create(type_object, result)
            else
              default_value(*path)
            end
    value
  end

  def write(*path, value)
    validate_path!(*path)
    current_value = read(*path)

    # If the value is different, update the state
    unless current_value.eq(value).value
      @block_data.set(*path, value.value)
      @on_change.call(path, value) if @on_change
    end
  end

  def persist(block_number)
    changes = @block_data.changes
    return if changes.empty?

    # Save block changes before applying changes
    @block_data.save_block_changes(block_number)

    # Build a single JSON object with all updates
    update_json = changes.each_with_object({}) do |(path, change), acc|
      current = acc
      path.each_with_index do |segment, idx|
        segment_key = segment.to_s
        if idx == path.length - 1
          current_value = @block_data.get(*path)
          current[segment_key] = current_value
        else
          current[segment_key] ||= {}
          current = current[segment_key]
        end
      end
    end

    # Debugging output to ensure the update_json is correct
    puts "Update JSON: #{update_json.inspect}"

    # Perform incremental update using PostgreSQL JSONB functions
    set_operations = build_jsonb_set_operations(update_json)
    sql = "UPDATE #{contract.class.table_name} SET current_state = #{set_operations} WHERE id = #{contract.id}"
    ActiveRecord::Base.connection.execute(sql)
  end

  def rollback_to_block(block_number)
    @block_data.rollback_to_block(block_number)

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
        if layout.name == :mapping || layout.name == :array
          layout = layout.value_type
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
          layout = layout.value_type
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
      jsonb_path = json_path_for(key)
      value_json = value.is_a?(Hash) ? value.to_json : value.to_json
      "jsonb_set(#{operations}, '{#{jsonb_path}}'::text[], '#{value_json}'::jsonb)"
    end
  end

  def json_path_for(key)
    key.split('.').map { |k| "\"#{k}\"" }.join(',')
  end
end
