require 'pg'
require 'English'
require 'manageiq/appliance_console/postgres_admin'

module ManageIQ
module ApplianceConsole
  class DatabaseReplication
    include ManageIQ::ApplianceConsole::Logging
    include ManageIQ::ApplianceConsole::Prompts

    PGPASS_FILE       = '/var/lib/pgsql/.pgpass'.freeze
    NETWORK_INTERFACE = 'eth0'.freeze

    REPGMR_FILE_LOCATIONS = {
      "repmgr10" => {
        "config" => "/etc/repmgr/10/repmgr.conf",
        "log"    => "/var/log/repmgr/repmgrd.log"
      },
      "repmgr13" => {
        "config" => "/etc/repmgr/13/repmgr.conf",
        "log"    => "/var/log/repmgr/repmgrd-13.log"
      }
    }.freeze

    attr_accessor :node_number, :database_name, :database_user,
                  :database_password, :primary_host

    def network_interfaces
      @network_interfaces ||= LinuxAdmin::NetworkInterface.list.reject(&:loopback?)
    end

    def ask_for_unique_cluster_node_number
      self.node_number = ask_for_integer("number uniquely identifying this node in the replication cluster")
    end

    def ask_for_database_credentials
      ask_for_cluster_database_credentials
      self.primary_host = ask_for_ip_or_hostname("primary database hostname or IP address", primary_host)
    end

    def confirm
      clear_screen
      say(<<-EOL)
Replication Server Configuration

        Cluster Node Number:        #{node_number}
        Cluster Database Name:      #{database_name}
        Cluster Database User:      #{database_user}
        Cluster Database Password:  "********"
        Cluster Primary Host:       #{primary_host}
        EOL
    end

    def self.repmgr_config
      repmgr_file_locations["config"]
    end

    def self.repmgr_configured?
      File.exist?(repmgr_config)
    end

    def self.repmgr_file_locations
      REPGMR_FILE_LOCATIONS[repmgr_service_name]
    end

    def self.repmgr_log
      repmgr_file_locations["log"]
    end

    def self.repmgr_service_name
      @repmgr_service_name ||= File.exist?(REPGMR_FILE_LOCATIONS["repmgr13"]["config"]) ? "repmgr13" : "repmgr10"
    end

    delegate :repmgr_config, :repmgr_configured?, :repmgr_file_locations, :repmgr_log, :repmgr_service_name, :to => self

    def confirm_reconfiguration
      say("Warning: File #{repmgr_config} exists. Replication is already configured")
      logger.warn("Warning: File #{repmgr_config} exists. Replication is already configured")
      agree("Continue with configuration? (Y/N): ")
    end

    def create_config_file(host)
      File.write(repmgr_config, config_file_contents(host))
      true
    end

    def config_file_contents(host)
      service_name = PostgresAdmin.service_name
      # FYI, 5.0 made quoting strings strict.  Always use single quoted strings.
      # https://repmgr.org/docs/current/release-5.0.html
      <<-EOS.strip_heredoc
        node_id='#{node_number}'
        node_name='#{host}'
        conninfo='host=#{host} user=#{database_user} dbname=#{database_name}'
        use_replication_slots='1'
        pg_basebackup_options='--wal-method=stream'
        failover='automatic'
        promote_command='repmgr standby promote -f #{repmgr_config} --log-to-file'
        follow_command='repmgr standby follow -f #{repmgr_config} --log-to-file --upstream-node-id=%n'
        log_file='#{repmgr_log}'
        service_start_command='sudo systemctl start #{service_name}'
        service_stop_command='sudo systemctl stop #{service_name}'
        service_restart_command='sudo systemctl restart #{service_name}'
        service_reload_command='sudo systemctl reload #{service_name}'
        data_directory='#{PostgresAdmin.data_directory}'
      EOS
    end

    def write_pgpass_file
      File.open(PGPASS_FILE, "w") do |f|
        f.write("*:*:#{database_name}:#{database_user}:#{database_password}\n")
        f.write("*:*:replication:#{database_user}:#{database_password}\n")
      end

      FileUtils.chmod(0600, PGPASS_FILE)
      FileUtils.chown("postgres", "postgres", PGPASS_FILE)
      true
    end

    private

    def ask_for_cluster_database_credentials
      self.database_name     = just_ask("cluster database name", database_name)
      self.database_user     = just_ask("cluster database username", database_user)
      self.database_password = ask_for_new_password("cluster database password", :default => database_password)
    end

    def run_repmgr_command(cmd, params = {})
      pid = fork do
        Process::UID.change_privilege(Process::UID.from_name("postgres"))
        begin
          res = AwesomeSpawn.run!(cmd, :params => params, :env => {"PGPASSWORD" => database_password})
          say(res.output)
        rescue AwesomeSpawn::CommandResultError => e
          say(e.result.output)
          say(e.result.error)
          say("")
          say("Failed to configure replication server")
          raise
        end
      end

      pid, status = Process.wait2(pid)
      status.success?
    end

    def primary_connection_hash
      {
        :dbname   => database_name,
        :host     => primary_host,
        :user     => database_user,
        :password => database_password
      }
    end
  end # class DatabaseReplication
end # module ApplianceConsole
end
