module ManageIQ
module ApplianceConsole
  class DatabaseReplicationPrimary < DatabaseReplication
    include ManageIQ::ApplianceConsole::Logging

    REGISTER_CMD = 'repmgr primary register'.freeze

    def initialize
      self.node_number       = nil
      self.database_name     = "vmdb_production"
      self.database_user     = "root"
      self.database_password = nil
      self.primary_host      = network_interfaces.first&.address
    end

    def ask_questions
      clear_screen
      say("Establish Primary Replication Server\n")
      ask_for_unique_cluster_node_number
      ask_for_database_credentials
      return false if repmgr_configured? && !confirm_reconfiguration
      confirm
    end

    def confirm
      super
      agree("Apply this Replication Server Configuration? (Y/N): ")
    end

    def activate
      say("Configuring Primary Replication Server...")
      create_config_file(primary_host) &&
        run_repmgr_command(REGISTER_CMD) &&
        write_pgpass_file
    end
  end # class DatabaseReplicationPrimary < DatabaseReplication
end # module ApplianceConsole
end
