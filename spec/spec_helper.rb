RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!
  config.expose_dsl_globally = true
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Requires supporting files with custom matchers and macros, etc, in spec/support/ and its subdirectories.
Dir[File.expand_path(File.join(__dir__, "support/**/*.rb"))].each { |f| require f }

require "manageiq-appliance_console"
ApplianceConsole::Logging.logger = Logger.new("/dev/null")

# For encryption rspec matchers
require "manageiq-gems-pending"
Dir[ManageIQ::Gems::Pending.root.join("spec/support/custom_matchers/*.rb")].each { |f| require f }
