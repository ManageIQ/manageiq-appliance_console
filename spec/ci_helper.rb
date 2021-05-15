require "linux_admin"

require_relative 'support/mixins/pg_environment_updater'

class CiPostgresRunner
  PGVER       = "10".freeze
  PGDATADIR   = "/var/ramfs/postgresql/#{PGVER}/main".freeze
  PGCONFIGDIR = "/etc/postgresql/#{PGVER}/main".freeze

  def self.start
    # Make sure we have our postgresql.conf in the right spot on Travis
    system("sudo cp #{PGDATADIR}/postgresql.conf #{PGCONFIGDIR}/postgresql.conf")

    # Make sure directly in the postgresql.conf, the data_directory is set
    # (requirement for pg_wrapper I think...)
    system("sudo sed -i -e \"\\$adata_directory = '#{PGDATADIR}'\" #{PGCONFIGDIR}/postgresql.conf")

    # Finally, restart the postgres service
    system("sudo systemctl start postgresql@10-main", :out => File::NULL)
  end

  def self.stop
    system("sudo systemctl stop postgresql", :out => File::NULL)
  end
end

# Override LinuxAdmin::Service.new to return CiPostgresRunner if the
# service_name is the configured postgresql service name
module LinuxAdmin
  def Service.new(*args)
    if ManageIQ::ApplianceConsole::PostgresAdmin.service_name == args.first
      CiPostgresRunner
    else
      # original new implementation (super didn't work properly...)
      if self == LinuxAdmin::Service
        service_type.new(*args)
      else
        orig_new(*args)
      end
    end
  end
end

# Since we will be loading this file in a non-rspec context to get the
# overrides from above but with elevated root permissions, only include the
# RSpec.configure if `RSpec` is defined.
if defined?(RSpec)
  RSpec.configure do |config|
    config.add_setting :with_postgres_specs, :default => true

    config.before(:suite) do
      ENV["APPLIANCE_PG_DATA"]    = CiPostgresRunner::PGDATADIR
      ENV["APPLIANCE_PG_SERVICE"] = "ci_pg_instance"

      PgEnvironmentUpdater.create_root_role
      PgEnvironmentUpdater.create_stub_manageiq_configs_on_ci
    end
  end
else
  # If loaded in a non-rspec context, ensure that logger is setup, without
  # needing the reset of lib/mangeiq-appliance_console.rb to be loaded.
  module ManageIQ
    module ApplianceConsole
      def self.logger
        @logger ||= Logger.new(File::NULL)
      end
    end
  end
end
