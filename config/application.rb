require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EthscriptionsVm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    config.middleware.insert_after ActionDispatch::Static, Rack::Deflater
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore
    
    config.autoload_paths << Rails.root.join('lib')
    
    loader = Rails.autoloaders.main
    loader.inflector.inflect(
      'open_mint_erc20_token' => 'OpenMintERC20Token',
      'erc20_token' => 'ERC20Token',
      'erc20' => 'ERC20',
      'erc721' => 'ERC721'
    )
    
    config.api_only = true
  end
end
