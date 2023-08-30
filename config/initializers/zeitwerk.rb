Rails.application.config.to_prepare do
  Rails.autoloaders.main.inflector = ErcFixInflector.new
end
