task :get => :environment do
  puts "Getting fresh backup..."
  PostgresClient.new.restore!
end

task :swap => :environment do
  puts "Getting fresh backup..."
  PostgresClient.new.swap_in!
end
