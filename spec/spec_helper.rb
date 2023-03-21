if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

# In GitHub Actions (CI), we do not have a tty, so the various tests that use
# STDIN in order to test interactivity will fail. This code creates a psuedo-tty
# in that environment. If you want to test locally in a "non-tty" way, you can
# run the tests as follows: `true | bundle exec rake 2>&1 | cat`
unless STDIN.tty?
  require "pty"
  require "io/console"
  _master_io, slave_file = PTY.open
  slave_file.raw!
  STDIN.reopen(slave_file)
end

require "manageiq-appliance_console"
ManageIQ::ApplianceConsole.logger = Logger.new("/dev/null")

require "manageiq/password/rspec_matchers"

# Requires supporting files with custom matchers and macros, etc, in spec/support/ and its subdirectories.
Dir[File.expand_path(File.join(__dir__, "support/**/*.rb"))].each { |f| require f }

RSpec.configure do |config|
  require "awesome_spawn/spec_helper"
  include AwesomeSpawn::SpecHelper

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!
  config.expose_dsl_globally = true
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    @old_key_root = ManageIQ::Password.key_root
    ManageIQ::Password.key_root = File.join(__dir__, "support")
  end

  config.after do
    ManageIQ::Password.key_root = @old_key_root
  end

  unless config.respond_to?(:with_postgres_specs)
    config.add_setting :with_postgres_specs, :default => false
  end
end
