module InstrumentAllMethods
  # GLOBAL_METHOD_STATS = Hash.new { |hash, key| hash[key] = Hash.new { |h, k| h[k] = { count: 0, total_time: 0.0 } } }
  # @relevant_methods = Set.new
  # @currently_wrapping = Set.new
  
  # def self.included(base)
  #   base.extend ClassMethods
  #   instrument_class(base)
  # end

  # def self.instrument_class(klass)
  #   klass.class_eval do
  #     def self.method_added(method_name)
  #       return if @instrumenting
  #       return if [
  #         :method_added,
  #         :singleton_method_added,
  #         :inherited
  #       ].include?(method_name)

  #       @instrumenting = true
  #       InstrumentAllMethods.add_relevant_method(self, method_name)
  #       InstrumentAllMethods.wrap_method(self, method_name)
  #       @instrumenting = false
  #     end

  #     def self.singleton_method_added(method_name)
  #       return if @instrumenting
  #       return if [
  #         :method_added,
  #         :singleton_method_added,
  #         :inherited
  #       ].include?(method_name)

  #       @instrumenting = true
  #       InstrumentAllMethods.add_relevant_method(singleton_class, method_name)
  #       InstrumentAllMethods.wrap_method(singleton_class, method_name)
  #       @instrumenting = false
  #     end

  #     def self.inherited(subclass)
  #       super(subclass)
  #       InstrumentAllMethods.instrument_class(subclass)
  #     end
  #   end

  #   # Add already defined methods to relevant methods set and wrap them
  #   klass.instance_methods(false).each { |method_name| add_relevant_method_and_wrap(klass, method_name) }
  #   klass.singleton_methods(false).each { |method_name| add_relevant_method_and_wrap(klass.singleton_class, method_name) }
  # end

  # def self.add_relevant_method_and_wrap(klass, method_name)
  #   add_relevant_method(klass, method_name)
  #   wrap_method(klass, method_name)
  # end

  # def self.add_relevant_method(klass, method_name)
  #   normalized_class_name = normalize_class_name(klass)
  #   binding.pry if normalized_class_name.nil?
  #   @relevant_methods << [normalized_class_name, method_name]
  # end

  # def self.wrap_method(klass, method_name)
  #   normalized_class_name = normalize_class_name(klass)
  #   @currently_wrapping << [klass, method_name]

  #   original_method = klass.instance_method(method_name)
  #   klass.define_method(method_name) do |*args, **kwargs, &block|
  #     start_time = Time.now

  #     # Profile the method using ruby-prof
  #     result = if InstrumentAllMethods.profile?(normalized_class_name, method_name)
  #                RubyProf.start
  #                result = original_method.bind(self).call(*args, **kwargs, &block)
  #                profile = RubyProf.stop
  #                InstrumentAllMethods.save_profile(normalized_class_name, method_name, profile)
  #                result
  #              else
  #                original_method.bind(self).call(*args, **kwargs, &block)
  #              end

  #     elapsed_time = Time.now - start_time

  #     method_stats = GLOBAL_METHOD_STATS[normalized_class_name][method_name]
  #     method_stats[:count] += 1
  #     method_stats[:total_time] += elapsed_time

  #     result
  #   end

  #   @currently_wrapping.delete([klass, method_name])
  # end

  # def self.profile?(klass, method)
  #   # Define logic to determine if a method should be profiled
  #   # For example, based on specific method names or class names
  #   # Here, we profile all methods that have been executed more than 10 times
  #   # stats = GLOBAL_METHOD_STATS[klass][method]
  #   # stats && stats[:count] > 10
    
  #   # method == :swapTokensForExactTokens
  # end

  # def self.save_profile(klass, method, profile)
  #   return
  #   # Save the profile results to a file
  #   FileUtils.mkdir_p('profiles')
  #   # Save flat profile
  #   flat_file = File.open("profiles/#{klass}_#{method}_profile_flat.txt", 'w+')
  #   RubyProf::FlatPrinter.new(profile).print(flat_file)
  #   flat_file.close

  #   # Save graph profile
  #   graph_file = File.open("profiles/#{klass}_#{method}_profile_graph.html", 'w+')
  #   RubyProf::GraphHtmlPrinter.new(profile).print(graph_file)
  #   graph_file.close

  #   # Save call tree profile (callgrind format)
  #   # call_tree_file = File.open("profiles/#{klass}_#{method}_profile_callgrind.txt", 'w+')
  #   # RubyProf::CallTreePrinter.new(profile).print(call_tree_file)
  #   # call_tree_file.close
  # end
  
  # def self.normalize_class_name(klass, receiver = nil)
  #   res = if klass.singleton_class?
  #     receiver_class = receiver ? receiver.class : nil
  #     (receiver_class ? receiver_class.name : klass.name) || klass.inspect.split(":").first
  #   else
  #     klass.name || klass.inspect.split(":").first
  #   end
  #   binding.pry if res.nil?
  #   res
  # end

  # def self.print_global_stats
  #   # CSV.open("method_stats.csv", "wb") do |csv|
  #   #   csv << ["Class", "Method", "Count", "Total Time (ms)", "Average Time (ms)"]
  #   #   GLOBAL_METHOD_STATS.each do |klass, methods|
  #   #     puts "\nClass: #{klass}"
  #   #     methods.each do |method, stats|
  #   #       total_time_ms = stats[:total_time] * 1000
  #   #       avg_time_ms = stats[:count] > 0 ? (total_time_ms / stats[:count]) : 0
  #   #       puts "  Method: #{method}, Count: #{stats[:count]}, Total Time: #{total_time_ms.round(3)}ms, Average Time: #{avg_time_ms.round(3)}ms"
  #   #       csv << [klass, method, stats[:count], total_time_ms.round(3), avg_time_ms.round(3)]
  #   #     end
  #   #   end
  #   # end
    
  #   # puts "\nMethod Execution Statistics (in ms):"
  #   # GLOBAL_METHOD_STATS.each do |klass, methods|
  #   #   puts "\nClass: #{klass}"
  #   #   methods.each do |method, stats|
  #   #     total_time_ms = stats[:total_time] * 1000
  #   #     avg_time_ms = stats[:count] > 0 ? (total_time_ms / stats[:count]) : 0
  #   #     puts "  Method: #{method}, Count: #{stats[:count]}, Total Time: #{total_time_ms.round(3)}ms, Average Time: #{avg_time_ms.round(3)}ms"
  #   #   end
  #   # end
  # end

  # module ClassMethods
  #   def instance_method_stats
  #     GLOBAL_METHOD_STATS[self.name]
  #   end
  # end
end
