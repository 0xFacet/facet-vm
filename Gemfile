source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.1"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.3.3"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 6.4.0"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem "redis", "~> 4.0"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "pry"
  gem "rspec-rails"
  gem 'rswag-specs'
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
  gem "stackprof"
  gem "active_record_query_trace", "~> 1.8"
end

group :production do
  gem 'cloudflare-rails'
end

gem "dotenv-rails", "~> 2.8", groups: [:development, :test]

gem "httpparty", "~> 0.2.0"

gem "clockwork", "~> 3.0"

gem "dalli", "~> 3.2"

gem "kaminari", "~> 1.2"

gem "airbrake", "~> 13.0"

gem "rack-cors", "~> 2.0"

gem "eth", "~> 0.5.11"

gem "activerecord-import", "~> 1.5"

gem "parser", "3.3.1.0"
gem "unparser"

gem "scout_apm", "~> 5.3"

gem "memoist", "~> 0.16.2"

gem "awesome_print", "~> 1.9"

gem "clipboard"

gem "descriptive_statistics", "~> 2.5"

gem 'facet_rails_common', git: 'https://github.com/0xfacet/facet_rails_common.git'

gem 'rswag-api'
gem 'rswag-ui'

gem 'newrelic_rpm'

gem "sqlite3", "~> 1.7"

gem "rubocop"

gem "memery", "~> 1.5"
