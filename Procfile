web: bundle exec puma -C config/puma.rb
release: rake db:migrate contract_artifacts:load
get_ethscriptions: bundle exec clockwork config/clock.rb
process_ethscriptions: bundle exec clockwork config/processor_clock.rb
