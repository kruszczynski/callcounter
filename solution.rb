# NewRelic Metaprogramming Challange 2014
# Author: Jan Grodowski, jgrodowski@gmail.com, http://github.com/grodowski

def define_count_wrapper(klass = self)  
  # TODO: handle optional method arguments
  
  klass.send(:alias_method, :watched_method, $watch_name)

  klass.class_eval do
    args = instance_method($watch_name.to_sym).parameters
    args_list = args.map { |arg| arg[1] }
    wrapper_method = Proc.new { |*args_list| $call_count += 1; watched_method *args_list }
    define_method $watch_name, wrapper_method 
    puts 'Ready!'
  end
end

def hook_into!(klass)
  klass = klass.singleton_class if $watch_type == :class_method
  puts "Initializing hooks: [class: #{klass}, watch_name: #{$watch_name}, watch_type: #{$watch_type}]"
  klass.class_eval do
    # setup the watch method - either directly or by waiting for the method
    # to be added using the method_added hook
    
    if method_defined?($watch_name)
      puts "Adding count wrapper to #{$watch_name}..."
      define_count_wrapper klass
    else
      # need to add callback to method_added and define wrapper
      # when method is actually added to the target class
      $_has_watch_method = false
    
      # we have to watch for method_added or singleton_method_added 
      # depending on the chosed method signature to watch for
      singleton = $watch_type == :class_method ? 'singleton_' : nil
      klass.class_eval do
        receiver = singleton ? self : self.singleton_class
        receiver.send :define_method, "#{singleton}method_added" do |method_name|
          if method_name.to_s == $watch_name && !$_has_watch_method
            $_has_watch_method = true
            puts 'Adding watch method...'        
            class_eval do 
              define_count_wrapper klass
            end
          end
        end
      end
      
    end
  
    # setup hooks to wait for methods to be included
    # and wrap the module method
    if $watch_type == :instance
      def self.include(included_module)
        if included_module.instance_methods.include?($watch_name.to_sym)
          included_module.class_eval do
            define_count_wrapper
          end
        end
        super(included_module)
      end
    end
  
    # setup hooks for methods to be extended
    # and wrap the module method
    if $watch_type == :class_method
      def extend(extended_module)
        if extended_module.instance_methods.include?($watch_name.to_sym)
          extended_module.class_eval do 
            define_count_wrapper
          end
        end
        super(extended_module)
      end
    end
  
  end
end

argument_str = ENV['COUNT_CALLS_TO']

arr_hash = argument_str.split('#')
arr_dot = argument_str.split('.')

$call_count = 0
$watch_class, $watch_name, $watch_type = if arr_hash.size == 2
  arr_hash << :instance
elsif arr_dot.size == 2
  arr_dot << :class_method
else
  raise 'COUNT_CALLS_TO has invalid format'
end
  
begin   
  klass = Object.const_get($watch_class)
  hook_into! klass
rescue NameError => e
  # klass = Object.const_set($watch_class, Class.new)
  # this approach is wrong, as it fails when the class inherits
  # from something else than Object
  
  # instead, when target const is not set yet,
  # try to hook into Object.inherited(superclass) to wait for it
  class Object
    def self.inherited(subclass)
      super(subclass)
      if subclass.to_s == $watch_class
        hook_into! subclass
        puts "Hooking into #{subclass}..."
      end
    end
  end
end

at_exit do 
  puts "The method #{$watch_class}#{$watch_type == :instance ? '#' : '.'}#{$watch_name} has been invoked #{$call_count} times"
end

