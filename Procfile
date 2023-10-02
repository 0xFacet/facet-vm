web: bundle exec puma -C config/puma.rb
release: rake db:migrate
get_ethscriptions: bundle exec clockwork config/clock.rb
process_ethscriptions: bundle exec clockwork config/processor_clock.rb
