class ApplicationController < ActionController::API
  private
  
  def convert_int_to_string(result)
    result = result.as_json

    case result
    when Numeric
      result.to_s
    when Hash
      result.deep_transform_values { |value| convert_int_to_string(value) }
    when Array
      result.map { |value| convert_int_to_string(value) }
    else
      result
    end
  end
end
