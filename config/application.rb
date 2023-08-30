require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EthscriptionsVm
  class Application < Rails::Application
    config.load_defaults 7.0

    config.middleware.insert_after ActionDispatch::Static, Rack::Deflater
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore
    
    config.autoload_paths << Rails.root.join('lib')
    
    config.api_only = true
  end
end
