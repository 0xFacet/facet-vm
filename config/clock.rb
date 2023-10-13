require 'clockwork'
require './config/boot'
require './config/environment'
require 'active_support/time'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  error_handler do |error|
    report_exception_every = 15.minutes
    
    exception_key = ["clockwork-airbrake", error.class, error.message, error.backtrace[0]].to_cache_key
    
    last_reported_at = Rails.cache.read(exception_key)

    if last_reported_at.blank? || (Time.zone.now - last_reported_at > report_exception_every)
      Airbrake.notify(error)
      Rails.cache.write(exception_key, Time.zone.now)
    end
  end

  every(6.seconds, 'Sync ethscriptions') do
    EthscriptionSync.import_eth_blocks_until_done
  end
  
  every(2.minutes, 'check_for_reorgs') do
    EthscriptionSync.check_for_reorgs
  end
end
