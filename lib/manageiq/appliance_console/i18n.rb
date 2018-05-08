require 'i18n'
require 'pathname'

gem_root = Pathname.new(__dir__).join("..", "..", "..")

locales_dir = ENV['CONTAINER'] ? "container" : "appliance"
locales_paths = [
  gem_root.join("locales", locales_dir, "*.yml"),
  File.expand_path(File.join("productization/appliance_console/locales", locales_dir, "*.yml"), ManageIQ::ApplianceConsole::RAILS_ROOT)
]
locales_paths.each { |p| I18n.load_path += Dir[p].sort }
I18n.enforce_available_locales = true
I18n.backend.load_translations
