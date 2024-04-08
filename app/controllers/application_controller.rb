class ApplicationController < ActionController::API
  include FacetRailsCommon::ApplicationControllerMethods
  
  def api_version
    params.fetch(:api_version, '1')
  end
  
  def cursor_mode?
    !!(
      api_version.to_i >= 2 ||
      params[:user_cursor_pagination] ||
      params[:use_cursor_pagination] ||
      params[:page_key]
    )
  end
end
