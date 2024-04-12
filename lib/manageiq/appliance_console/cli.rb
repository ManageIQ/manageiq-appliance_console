require 'optimist'
require 'pathname'

# support for appliance_console methods
unless defined?(say)
  def say(arg)
    puts(arg)
  end
end

module ManageIQ
module ApplianceConsole
  class CliError < StandardError; end

  class Cli
    attr_accessor :options

    # machine host
    def host
      options[:host] || LinuxAdmin::Hosts.new.hostname
    end

    # database hostname
    def hostname
      options[:internal] ? "localhost" : options[:hostname]
    end

    def local?(name = hostname)
      name.presence.in?(["localhost", "127.0.0.1", nil])
    end

    def set_host?
      options[:host]
    end

    def key?
      options[:key] || options[:fetch_key] || (local_database? && !key_configuration.key_exist?)
    end

    def database?
      (options[:standalone] || hostname) && !database_admin?
    end

    def database_admin?
      db_dump? || db_backup? || db_restore?
    end

    def db_dump?
      options[:dump]
    end

    def db_backup?
      options[:backup]
    end

    def db_restore?
      options[:restore]
    end

    def local_database?
      database? && (local?(hostname) || options[:standalone])
    end

    def certs?
      options[:http_cert]
    end

    def uninstall_ipa?
      options[:uninstall_ipa]
    end

    def install_ipa?
      options[:ipaserver]
    end

    def tmp_disk?
      options[:tmpdisk]
    end

    def log_disk?
      options[:logdisk]
    end

    def extauth_opts?
      options[:extauth_opts]
    end

    def saml_config?
      options[:saml_config]
    end

    def saml_unconfig?
      options[:saml_unconfig]
    end

    def message_server_config?
      options[:message_server_config]
    end

    def message_server_unconfig?
      options[:message_server_unconfig]
    end

    def message_client_config?
      options[:message_client_config]
    end

    def message_client_unconfig?
      options[:message_client_unconfig]
    end

    def oidc_config?
      options[:oidc_config]
    end

    def oidc_unconfig?
      options[:oidc_unconfig]
    end

    def set_server_state?
      options[:server]
    end

    def set_replication?
      options[:cluster_node_number] && options[:password] && replication_params?
    end

    def replication_params?
      options[:replication] == "primary" || (options[:replication] == "standby" && options[:primary_host])
    end

    def openscap?
      options[:openscap]
    end

    def initialize(options = {})
      self.options = options
    end

    def disk_from_string(path)
      return if path.blank?
      path == "auto" ? disk : disk_by_path(path)
    end

    def disk
      LinuxAdmin::Disk.local.detect { |d| d.partitions.empty? }
    end

    def disk_by_path(path)
      LinuxAdmin::Disk.local.detect { |d| d.path == path }
    end

    def parse(args)
      args.shift if args.first == "--" # Handle when called through script/runner
      self.options = Optimist.options(args) do
        banner "Usage: appliance_console_cli [options]"

        opt :host,                        "/etc/hosts name",                                                :type => :string,  :short => 'H'
        opt :region,                      "Region Number",                                                  :type => :integer, :short => "r"
        opt :internal,                    "Internal Database",                                                                 :short => 'i'
        opt :hostname,                    "Database Hostname",                                              :type => :string,  :short => 'h'
        opt :port,                        "Database Port",                                                  :type => :integer,                :default => 5432
        opt :username,                    "Database Username",                                              :type => :string,  :short => 'U', :default => "root"
        opt :password,                    "Database Password",                                              :type => :string,  :short => "p"
        opt :dbname,                      "Database Name",                                                  :type => :string,  :short => "d", :default => "vmdb_production"
        opt :local_file,                  "Source/Destination file for DB dump/backup/restore",             :type => :string,  :shoft => "l"
        opt :dump,                        "Perform a pg-dump"
        opt :backup,                      "Perform a pg-basebackup"
        opt :restore,                     "Restore a database dump/backup"
        opt :standalone,                  "Run this server as a standalone database server",                :type => :bool,    :short => 'S'
        opt :key,                         "Create encryption key",                                          :type => :boolean, :short => "k"
        opt :fetch_key,                   "SSH host with encryption key",                                   :type => :string,  :short => "K"
        opt :force_key,                   "Forcefully create encryption key",                               :type => :boolean, :short => "f"
        opt :sshlogin,                    "SSH login",                                                      :type => :string,  :default => "root"
        opt :sshpassword,                 "SSH password",                                                   :type => :string
        opt :replication,                 "Configure database replication as primary or standby",           :type => :string,  :short => :none
        opt :primary_host,                "Primary database host IP address",                               :type => :string,  :short => :none
        opt :standby_host,                "Standby database host IP address",                               :type => :string,  :short => :none
        opt :auto_failover,               "Configure Replication Manager (repmgrd) for automatic failover", :type => :bool,    :short => :none
        opt :cluster_node_number,         "Database unique cluster node number",                            :type => :integer, :short => :none
        opt :verbose,                     "Verbose",                                                        :type => :boolean, :short => "v"
        opt :dbdisk,                      "Database Disk Path",                                             :type => :string
        opt :logdisk,                     "Log Disk Path",                                                  :type => :string
        opt :tmpdisk,                     "Temp storage Disk Path",                                         :type => :string
        opt :uninstall_ipa,               "Uninstall IPA Client",                                           :type => :boolean, :default => false
        opt :ipaserver,                   "IPA Server FQDN",                                                :type => :string
        opt :ipaprincipal,                "IPA Server principal",                                           :type => :string,  :default => "admin"
        opt :ipapassword,                 "IPA Server password",                                            :type => :string
        opt :ipadomain,                   "IPA Server domain (optional)",                                   :type => :string
        opt :iparealm,                    "IPA Server realm (optional)",                                    :type => :string
        opt :ca,                          "CA name used for certmonger",                                    :type => :string,  :default => "ipa"
        opt :http_cert,                   "install certs for http server",                                  :type => :boolean
        opt :extauth_opts,                "External Authentication Options",                                :type => :string
        opt :saml_config,                 "Configure Appliance for SAML Authentication",                    :type => :boolean, :default => false
        opt :saml_client_host,            "Optional Appliance host used for SAML registration",             :type => :string
        opt :saml_idp_metadata,           "The file path or URL of the SAML IDP Metadata",                  :type => :string
        opt :saml_enable_sso,             "Optionally enable SSO with SAML Authentication",                 :type => :boolean, :default => false
        opt :saml_unconfig,               "Unconfigure Appliance SAML Authentication",                      :type => :boolean, :default => false
        opt :oidc_config,                 "Configure Appliance for OpenID-Connect Authentication",          :type => :boolean, :default => false
        opt :oidc_url,                    "The OpenID-Connect Provider URL",                                :type => :string
        opt :oidc_client_host,            "Optional Appliance host used for OpenID-Connect Authentication", :type => :string
        opt :oidc_client_id,              "The OpenID-Connect Provider Client ID",                          :type => :string
        opt :oidc_client_secret,          "The OpenID-Connect Provider Client Secret",                      :type => :string
        opt :oidc_insecure,               "OpenID-Connect Insecure No SSL Verify (development)",            :type => :boolean, :default => false
        opt :oidc_introspection_endpoint, "The OpenID-Connect Provider Introspect Endpoint",                :type => :string
        opt :oidc_enable_sso,             "Optionally enable SSO with OpenID-Connect Authentication",       :type => :boolean, :default => false
        opt :oidc_unconfig,               "Unconfigure Appliance OpenID-Connect Authentication",            :type => :boolean, :default => false
        opt :server,                      "{start|stop|restart} actions on evmserverd Server",              :type => :string
        opt :openscap,                    "Setup OpenScap",                                                 :type => :boolean, :default => false
        opt :message_server_config,       "Subcommand to   Configure Appliance as a Kafka Message Server",  :type => :boolean, :default => false
        opt :message_server_unconfig,     "Subcommand to Unconfigure Appliance as a Kafka Message Server",  :type => :boolean, :default => false
        opt :message_client_config,       "Subcommand to   Configure Appliance as a Kafka Message Client",  :type => :boolean, :default => false
        opt :message_client_unconfig,     "Subcommand to Unconfigure Appliance as a Kafka Message Client",  :type => :boolean, :default => false
        opt :message_keystore_username,   "Message Server Keystore Username",                               :type => :string
        opt :message_keystore_password,   "Message Server Keystore Password",                               :type => :string
        opt :message_server_username,     "Message Server Username",                                        :type => :string
        opt :message_server_password,     "Message Server password",                                        :type => :string
        opt :message_server_port,         "Message Server Port",                                            :type => :integer
        opt :message_server_use_ipaddr,   "Message Server Use Address",                                     :type => :boolean, :default => false
        opt :message_server_host,         "Message Server Hostname or IP Address",                          :type => :string
        opt :message_truststore_path_src, "Message Server Truststore Path",                                 :type => :string
        opt :message_ca_cert_path_src,    "Message Server CA Cert Path",                                    :type => :string
        opt :message_persistent_disk,     "Message Persistent Disk Path",                                   :type => :string
      end
      Optimist.die :region, "needed when setting up a local database" if region_number_required? && options[:region].nil?
      Optimist.die "Supply only one of --message-server-host or --message-server-use-ipaddr=true" if both_host_and_use_ip_addr_specified?
      Optimist.die "Supply only one of --message-server-config, --message-server-unconfig, --message-client-config or --message-client-unconfig" if multiple_message_subcommands?
      self
    end

    def both_host_and_use_ip_addr_specified?
      !options[:message_server_host].nil? && options[:message_server_use_ipaddr] == true
    end

    def multiple_message_subcommands?
      a = [options[:message_server_config], options[:message_server_unconfig], options[:message_client_config], options[:message_client_unconfig]]
      a.each_with_object(Hash.new(0)) { |o, h| h[o] += 1 }[true] > 1
    end

    def region_number_required?
      !options[:standalone] && local_database? && !database_admin?
    end

    def run
      Optimist.educate unless set_host? || key? || database? || db_dump? || db_backup? ||
                              db_restore? || tmp_disk? || log_disk? ||
                              uninstall_ipa? || install_ipa? || certs? || extauth_opts? ||
                              set_server_state? || set_replication? || openscap? ||
                              saml_config? || saml_unconfig? ||
                              oidc_config? || oidc_unconfig? ||
                              message_server_config? || message_server_unconfig? ||
                              message_client_config? || message_client_unconfig?

      if set_host?
        system_hosts = LinuxAdmin::Hosts.new
        system_hosts.hostname = options[:host]
        system_hosts.set_loopback_hostname(options[:host])
        system_hosts.save
      end
      create_key if key?
      set_db if database?
      set_replication if set_replication?
      db_dump if db_dump?
      db_backup if db_backup?
      db_restore if db_restore?
      config_tmp_disk if tmp_disk?
      config_log_disk if log_disk?
      uninstall_ipa if uninstall_ipa?
      install_ipa if install_ipa?
      install_certs if certs?
      extauth_opts if extauth_opts?
      saml_config if saml_config?
      saml_unconfig if saml_unconfig?
      oidc_config if oidc_config?
      oidc_unconfig if oidc_unconfig?
      openscap if openscap?
      message_server_config if message_server_config?
      message_server_unconfig if message_server_unconfig?
      message_client_config if message_client_config?
      message_client_unconfig if message_client_unconfig?
      # set_server_state must be after set_db and message_*_config so that a user
      # can configure database, messaging, and start the server in one command
      set_server_state if set_server_state?
    rescue CliError => e
      say(e.message)
      say("")
      exit(1)
    rescue AwesomeSpawn::CommandResultError => e
      say e.result.output
      say e.result.error
      say ""
      raise
    end

    def set_db
      raise "No encryption key (v2_key) present" unless key_configuration.key_exist?
      raise "A password is required to configure a database" unless password?
      if local?
        set_internal_db
      else
        set_external_db
      end
    end

    def password?
      options[:password] && !options[:password].strip.empty?
    end

    def set_internal_db
      say "configuring internal database"
      config = ManageIQ::ApplianceConsole::InternalDatabaseConfiguration.new({
        :database          => options[:dbname],
        :region            => options[:region],
        :username          => options[:username],
        :password          => options[:password],
        :interactive       => false,
        :disk              => disk_from_string(options[:dbdisk]),
        :run_as_evm_server => !options[:standalone]
      }.delete_if { |_n, v| v.nil? })
      config.check_disk_is_mount_point

      # create partition, pv, vg, lv, ext4, update fstab, mount disk
      # initdb, relabel log directory for selinux, update configs,
      # start pg, create user, create db update the rails configuration,
      # verify, set up the database with region. activate does it all!
      raise CliError, "Failed to configure internal database" unless config.activate
    rescue RuntimeError => e
      raise CliError, "Failed to configure internal database #{e.message}"
    end

    def set_external_db
      say "configuring external database"
      config = ManageIQ::ApplianceConsole::ExternalDatabaseConfiguration.new({
        :host        => options[:hostname],
        :port        => options[:port],
        :database    => options[:dbname],
        :region      => options[:region],
        :username    => options[:username],
        :password    => options[:password],
        :interactive => false,
      }.delete_if { |_n, v| v.nil? })

      # call create_or_join_region (depends on region value)
      raise CliError, "Failed to configure external database" unless config.activate
    end

    def set_replication
      if options[:replication] == "primary"
        db_replication = ManageIQ::ApplianceConsole::DatabaseReplicationPrimary.new
        say("Configuring Server as Primary")
      else
        db_replication = ManageIQ::ApplianceConsole::DatabaseReplicationStandby.new
        say("Configuring Server as Standby")
        db_replication.disk = disk_from_string(options[:dbdisk])
        db_replication.primary_host = options[:primary_host]
        db_replication.standby_host = options[:standby_host] if options[:standby_host]
        db_replication.run_repmgrd_configuration = options[:auto_failover] ? true : false
      end
      db_replication.database_name = options[:dbname] if options[:dbname]
      db_replication.database_user = options[:username] if options[:username]
      db_replication.node_number = options[:cluster_node_number]
      db_replication.database_password = options[:password]
      db_replication.activate
    end

    def db_dump
      PostgresAdmin.backup_pg_dump(extract_db_opts(options))
    end

    def db_backup
      PostgresAdmin.backup(extract_db_opts(options))
    end

    def db_restore
      PostgresAdmin.restore(extract_db_opts(options))
    end

    DB_OPT_KEYS = %i[dbname username password hostname port local_file].freeze
    def extract_db_opts(options)
      require 'manageiq/appliance_console/postgres_admin'

      db_opts = {}

      DB_OPT_KEYS.each { |k| db_opts[k] = options[k] if options[k] }

      if db_dump? && options[:exclude_table_data]
        db_opts[:exclude_table_data] = options[:exclude_table_data]
      end

      db_opts
    end

    def key_configuration
      @key_configuration ||= KeyConfiguration.new(
        :action   => options[:fetch_key] ? :fetch : :create,
        :force    => options[:fetch_key] ? true : options[:force_key],
        :host     => options[:fetch_key],
        :login    => options[:sshlogin],
        :password => options[:sshpassword],
      )
    end

    def create_key
      say "#{key_configuration.action} encryption key"
      unless key_configuration.activate
        say("Could not create encryption key (v2_key)")
        exit(1)
      end
    end

    def install_certs
      say "creating ssl certificates"
      config = CertificateAuthority.new(
        :hostname => host,
        :realm    => options[:iparealm],
        :ca_name  => options[:ca],
        :http     => options[:http_cert],
        :verbose  => options[:verbose],
      )

      config.activate
      say "\ncertificate result: #{config.status_string}"
      unless config.complete?
        say "After the certificates are retrieved, rerun to update service configuration files"
      end
    end

    def install_ipa
      raise "please uninstall ipa before reinstalling" if ExternalHttpdAuthentication.ipa_client_configured?
      config = ExternalHttpdAuthentication.new(
        host,
        :ipaserver => options[:ipaserver],
        :domain    => options[:ipadomain],
        :realm     => options[:iparealm],
        :principal => options[:ipaprincipal],
        :password  => options[:ipapassword],
      )

      config.post_activation if config.activate
    end

    def uninstall_ipa
      say "Uninstalling IPA-client"
      config = ExternalHttpdAuthentication.new
      config.deactivate if config.ipa_client_configured?
    end

    def openscap
      say("Configuring Openscap")
      ManageIQ::ApplianceConsole::Scap.new.lockdown
    end

    def config_tmp_disk
      if (tmp_disk = disk_from_string(options[:tmpdisk]))
        say "creating temp disk"
        config = ManageIQ::ApplianceConsole::TempStorageConfiguration.new(:disk => tmp_disk)
        config.activate
      else
        report_disk_error(options[:tmpdisk])
      end
    end

    def config_log_disk
      if (log_disk = disk_from_string(options[:logdisk]))
        say "creating log disk"
        config = ManageIQ::ApplianceConsole::LogfileConfiguration.new(:disk => log_disk)
        config.activate
      else
        report_disk_error(options[:logdisk])
      end
    end

    def report_disk_error(missing_disk)
      choose_disk = disk.try(:path)
      if choose_disk
        say "could not find disk #{missing_disk}"
        say "if you pass auto, it will choose: #{choose_disk}"
      else
        say "no disks with a free partition"
      end
    end

    def extauth_opts
      extauthopts = ExternalAuthOptions.new
      extauthopts_hash = extauthopts.parse(options[:extauth_opts])
      raise "Must specify at least one external authentication option to set" unless extauthopts_hash.present?
      extauthopts.update_configuration(extauthopts_hash)
    end

    def saml_config
      SamlAuthentication.new(options).configure(options[:saml_client_host] || host)
    end

    def saml_unconfig
      SamlAuthentication.new(options).unconfigure
    end

    def oidc_config
      OIDCAuthentication.new(options).configure(options[:oidc_client_host] || host)
    end

    def oidc_unconfig
      OIDCAuthentication.new(options).unconfigure
    end

    def message_server_config
      raise "Message Server Configuration is not available" unless MessageServerConfiguration.available?

      MessageServerConfiguration.new(options).configure
    end

    def message_server_unconfig
      MessageServerConfiguration.new(options).unconfigure
    end

    def message_client_config
      raise "Message Client Configuration is not available" unless MessageClientConfiguration.available?

      MessageClientConfiguration.new(options).configure
    end

    def message_client_unconfig
      MessageClientConfiguration.new(options).unconfigure
    end

    def set_server_state
      case options[:server]
      when "start"
        EvmServer.start unless EvmServer.running?
      when "stop"
        EvmServer.stop if EvmServer.running?
      when "restart"
        EvmServer.restart
      else
        raise "Invalid server action"
      end
    end

    def self.parse(args)
      new.parse(args).run
    end
  end
end
end
