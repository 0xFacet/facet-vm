task :pull_db => :environment do
  puts "Getting fresh backup..."
  PostgresClient.new.restore!
end

task :swap_in_db => :environment do
  puts "Getting fresh backup..."
  PostgresClient.new.swap_in!
end
