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
  
  def page_mode?
    !cursor_mode?
  end
  
  def v1_page_params
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    [page, per_page]
  end
end
