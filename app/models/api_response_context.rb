class ApiResponseContext < ActiveSupport::CurrentAttributes
  attribute :api_version
  
  def use_v2_api?
    api_version.blank? || api_version.to_i >= 2
  end
  
  def use_v1_api?
    !use_v2_api?
  end
end
