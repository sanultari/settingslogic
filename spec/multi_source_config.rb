class MultiSourceConfig < Settingslogic
  source "#{File.dirname(__FILE__)}/settings.yml"
  source "#{File.dirname(__FILE__)}/override.yml"
end
