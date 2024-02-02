class ApplicationController < ActionController::API
  before_action :authorize_all_requests_if_required
  around_action :use_read_only_database_if_available
  
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
  
  def authorized?
    authorization_header = request.headers['Authorization']
    return false if authorization_header.blank?
  
    token = authorization_header.remove('Bearer ').strip
    stored_tokens = JSON.parse(ENV.fetch('API_AUTH_TOKENS', "[]"))
    
    stored_tokens.include?(token)
  rescue JSON::ParserError
    Airbrake.notify("Invalid API_AUTH_TOKEN format: #{ENV.fetch('API_AUTH_TOKENS', "[]")}")
    false
  end
  
  def authorize_all_requests_if_required
    if ENV['REQUIRE_AUTHORIZATION'].present? && ENV['REQUIRE_AUTHORIZATION'] != 'false'
      unless authorized?
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
  
  def use_read_only_database_if_available
    if ENV['FOLLOWER_DATABASE_URL'].present?
      ActiveRecord::Base.connected_to(role: :reading) { yield }
    else
      yield
    end
  end
end
