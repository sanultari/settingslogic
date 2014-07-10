$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rspec'
require 'settingslogic'
require_relative 'settings'
require_relative 'settings2'
require_relative 'settings3'
require_relative 'settings4'
require_relative 'multi_source_config'
require_relative 'settings_empty'
require_relative 'commented_config'

# Needed to test Settings3
Object.send :define_method, 'collides' do
  'collision'
end

RSpec.configure do |config|
end
