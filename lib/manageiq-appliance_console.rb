module ManageIQ
  module ApplianceConsole
    require 'pathname'
    require 'tempfile'
    RAILS_ROOT = File.exist?("/var/www/miq/vmdb") ? Pathname.new("/var/www/miq/vmdb") : Pathname.new(Dir.mktmpdir)

    class << self
      attr_writer :logger
    end

    def self.logger
      @logger ||= ManageIQ::ApplianceConsole::Logger.instance
    end

    def self.logger=(logger)
      @logger = logger
    end
  end
end

require 'manageiq/appliance_console/highline_patch'

require 'manageiq/appliance_console/version'
require 'manageiq/appliance_console/errors'
require 'manageiq/appliance_console/logger'
require 'manageiq/appliance_console/logging'

require 'manageiq-gems-pending'

require 'manageiq/appliance_console/certificate'
require 'manageiq/appliance_console/certificate_authority'
require 'manageiq/appliance_console/cli'
require 'manageiq/appliance_console/database_configuration'
require 'manageiq/appliance_console/database_maintenance'
require 'manageiq/appliance_console/database_maintenance_hourly'
require 'manageiq/appliance_console/database_maintenance_periodic'
require 'manageiq/appliance_console/database_replication'
require 'manageiq/appliance_console/database_replication_primary'
require 'manageiq/appliance_console/database_replication_standby'
require 'manageiq/appliance_console/date_time_configuration'
require 'manageiq/appliance_console/external_auth_options'
require 'manageiq/appliance_console/external_database_configuration'
require 'manageiq/appliance_console/external_httpd_authentication'
require 'manageiq/appliance_console/internal_database_configuration'
require 'manageiq/appliance_console/key_configuration'
require 'manageiq/appliance_console/logfile_configuration'
require 'manageiq/appliance_console/logical_volume_management'
require 'manageiq/appliance_console/principal'
require 'manageiq/appliance_console/prompts'
require 'manageiq/appliance_console/scap'
require 'manageiq/appliance_console/temp_storage_configuration'
require 'manageiq/appliance_console/timezone_configuration'
require 'manageiq/appliance_console/utilities'
