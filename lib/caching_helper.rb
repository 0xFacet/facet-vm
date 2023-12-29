module CachingHelper
  def render_with_caching(
    cache_key,
    max_age: 1.second,
    error_if: -> { false },
    error_response: { error: 'Not found' },
    error_status: :not_found,
    &block
  )
    if error_if.call
      render json: error_response, status: error_status
    else
      if max_age.present?
        expires_in max_age, public: true
      end

      cache_key = Array.wrap(cache_key).to_cache_key(
        controller_path,
        action_name,
        CacheVersion.version,
        Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? SecureRandom.base64 : ''
      )
      
      if stale?(etag: cache_key, public: true)
        json = Rails.cache.fetch(cache_key) do
          (block.call || {}).to_json
        end
  
        render json: json
      end
    end
  end
  
  def self.included(base)
    base.send(:private, :render_with_caching)
  end
end
