require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EthscriptionsVm
  class Application < Rails::Application
    config.load_defaults 7.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    config.middleware.insert_after ActionDispatch::Static, Rack::Deflater
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore
    
    config.autoload_paths << Rails.root.join('lib')
    
    config.active_record.schema_format = :sql
    
    config.active_support.cache_format_version = 7.1
    
    config.api_only = true
  end
end
