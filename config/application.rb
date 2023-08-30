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
      'ethscription_erc20_bridge' => 'EthscriptionERC20Bridge',
      'erc20_liquidity_pool' => 'ERC20LiquidityPool',
      'ether_erc20_bridge' => 'EtherERC20Bridge',
      'generative_erc721' => 'GenerativeERC721',
      'open_edition_erc721' => 'OpenEditionERC721',
      'public_mint_erc20' => 'PublicMintERC20',
      'erc20' => 'ERC20',
      'erc721' => 'ERC721'
    )
    
    config.api_only = true
  end
end
