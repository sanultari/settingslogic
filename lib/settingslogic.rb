require "yaml"
require "erb"
require 'open-uri'

# A simple settings solution using a YAML file. See README for more information.
class Settingslogic < Hash
  class MissingSetting < StandardError; end

  class << self
    def name # :nodoc:
      self.superclass != Hash && instance.key?("name") ? instance.name : super
    end

    # Enables Settings.get('nested.key.name') for dynamic access
    def get(key)
      parts = key.split('.')
      curs = self
      while p = parts.shift
        curs = curs.send(p)
      end
      curs
    end

    def source(value = nil)
      @source ||= []
      @source << value
    end

    def namespace(value = nil)
      @namespace ||= value
    end

    def suppress_errors(value = nil)
      @suppress_errors ||= value
    end

    def [](key)
      instance.fetch(key.to_s, nil)
    end

    def []=(key, val)
      # Setting[:key][:key2] = 'value' for dynamic settings
      val = new(val, source) if val.is_a? Hash
      instance.store(key.to_s, val)
      instance.create_accessor_for(key, val)
    end

    def load!
      instance
      true
    end

    def reload!
      @instance = nil
      load!
    end

    private
      def instance
        return @instance if @instance
        @instance = new
        create_accessors!
        @instance
      end

      def method_missing(name, *args, &block)
        instance.send(name, *args, &block)
      end

      # It would be great to DRY this up somehow, someday, but it's difficult because
      # of the singleton pattern.  Basically this proxies Setting.foo to Setting.instance.foo
      def create_accessors!
        instance.each do |key,val|
          create_accessor_for(key)
        end
      end

      def create_accessor_for(key)
        return unless key.to_s =~ /^\w+$/  # could have "some-setting:" which blows up eval
        instance_eval "def #{key}; instance.send(:#{key}); end"
      end

  end

  # Initializes a new settings object. You can initialize an object in any of the following ways:
  #
  #   Settings.new(:application) # will look for config/application.yml
  #   Settings.new("application.yaml") # will look for application.yaml
  #   Settings.new("/var/configs/application.yml") # will look for /var/configs/application.yml
  #   Settings.new(:config1 => 1, :config2 => 2)
  #
  # Basically if you pass a symbol it will look for that file in the configs directory of your rails app,
  # if you are using this in rails. If you pass a string it should be an absolute path to your settings file.
  # Then you can pass a hash, and it just allows you to access the hash via methods.
  def initialize(hash_or_file = self.class.source, section = nil)
    raise Errno::ENOENT, "No file specified as Settingslogic source" if hash_or_file.nil?

    hash = hash_or_file
    hash = process_files(hash_or_file) unless hash.is_a? Hash
    self.replace hash

    @section = section || default_session_name  # so end of error says "in application.yml"
    create_accessors!
  end

  # Called for dynamically-defined keys, and also the first key deferenced at the top-level, if load! is not used.
  # Otherwise, create_accessors! (called by new) will have created actual methods for each key.
  def method_missing(name, *args, &block)
    key = name.to_s
    return missing_key("Missing setting '#{key}' in #{@section}") unless has_key? key
    value = fetch(key)
    create_accessor_for(key)
    value.is_a?(Hash) ? self.class.new(value, "'#{key}' section in #{@section}") : value
  end

  def [](key)
    fetch(key.to_s, nil)
  end

  def []=(key,val)
    # Setting[:key][:key2] = 'value' for dynamic settings
    val = self.class.new(val, @section) if val.is_a? Hash
    store(key.to_s, val)
    create_accessor_for(key, val)
  end

  # Returns an instance of a Hash object
  def to_hash
    Hash[self]
  end

  # This handles naming collisions with Sinatra/Vlad/Capistrano. Since these use a set()
  # helper that defines methods in Object, ANY method_missing ANYWHERE picks up the Vlad/Sinatra
  # settings!  So settings.deploy_to title actually calls Object.deploy_to (from set :deploy_to, "host"),
  # rather than the app_yml['deploy_to'] hash.  Jeezus.
  def create_accessors!
    self.each do |key,val|
      create_accessor_for(key)
    end
  end

  # Use instance_eval/class_eval because they're actually more efficient than define_method{}
  # http://stackoverflow.com/questions/185947/ruby-definemethod-vs-def
  # http://bmorearty.wordpress.com/2009/01/09/fun-with-rubys-instance_eval-and-class_eval/
  def create_accessor_for(key, val=nil)
    return unless key.to_s =~ /^\w+$/  # could have "some-setting:" which blows up eval
    instance_variable_set("@#{key}", val)
    self.class.class_eval <<-EndEval
      def #{key}
        return @#{key} if @#{key}
        return missing_key("Missing setting '#{key}' in #{@section}") unless has_key? '#{key}'
        value = fetch('#{key}')
        @#{key} = if value.is_a?(Hash)
          self.class.new(value, "'#{key}' section in #{@section}")
        elsif value.is_a?(Array) && value.all?{|v| v.is_a? Hash}
          value.map{|v| self.class.new(v)}
        else
          value
        end
      end
    EndEval
  end

  def symbolize_keys
    inject({}) do |memo, tuple|
      k = (tuple.first.to_sym rescue tuple.first) || tuple.first

      v = k.is_a?(Symbol) ? send(k) : tuple.last # make sure the value is accessed the same way Settings.foo.bar works

      memo[k] = v && v.respond_to?(:symbolize_keys) ? v.symbolize_keys : v #recurse for nested hashes

      memo
    end
  end

  def missing_key(msg)
    return nil if self.class.suppress_errors

    raise MissingSetting, msg
  end

  private
  def process_files(hash_or_file)
    files = hash_or_file.reject { |file| file.nil? }
    hash = load_from files
    if self.class.namespace
      hash = hash[self.class.namespace] or return missing_key("Missing setting '#{self.class.namespace}' in #{files.join(', ')}")
    end

    hash
  end

  def load_from(files)
    hash = {}
    files.each do |file|
      merge_config hash, file if File.exist? file
    end

    hash
  end

  def merge_config(hash, file_path)
    file_contents = open(file_path).read
    raw_result = YAML.load(ERB.new(file_contents).result)
    single_hash = raw_result ? raw_result : {}
    hash.merge! single_hash
  end

  def default_session_name
    self.class.source.reject { |file| file.nil? }.join(', ')
  end
end
