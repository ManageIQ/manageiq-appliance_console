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
  end
end

require 'manageiq/appliance_console/version'
require 'manageiq/appliance_console/errors'
require 'manageiq/appliance_console/logger'
require 'manageiq/appliance_console/logging'
require 'manageiq/appliance_console/prompts'

require 'highline'

require 'manageiq/appliance_console/auth_utilities'
require 'manageiq/appliance_console/certificate'
require 'manageiq/appliance_console/certificate_authority'
require 'manageiq/appliance_console/cli'
require 'manageiq/appliance_console/database_admin'
require 'manageiq/appliance_console/database_configuration'
require 'manageiq/appliance_console/database_replication'
require 'manageiq/appliance_console/database_replication_primary'
require 'manageiq/appliance_console/database_replication_standby'
require 'manageiq/appliance_console/external_auth_options'
require 'manageiq/appliance_console/external_database_configuration'
require 'manageiq/appliance_console/external_httpd_authentication'
require 'manageiq/appliance_console/evm_server'
require 'manageiq/appliance_console/internal_database_configuration'
require 'manageiq/appliance_console/key_configuration'
require 'manageiq/appliance_console/logfile_configuration'
require 'manageiq/appliance_console/logical_volume_management'
require 'manageiq/appliance_console/message_configuration_client'
require 'manageiq/appliance_console/message_configuration_server'
require 'manageiq/appliance_console/oidc_authentication'
require 'manageiq/appliance_console/principal'
require 'manageiq/appliance_console/saml_authentication'
require 'manageiq/appliance_console/scap'
require 'manageiq/appliance_console/temp_storage_configuration'
require 'manageiq/appliance_console/utilities'
