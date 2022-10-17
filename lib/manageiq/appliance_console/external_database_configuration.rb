module ManageIQ
module ApplianceConsole
  class ExternalDatabaseConfiguration < DatabaseConfiguration
    attr_accessor :action

    def initialize(hash = {})
      set_defaults
      super
    end

    def set_defaults
      self.username = "root"
      self.port     = DEFAULT_PORT
      self.database = "vmdb_production"
    end

    def activate
      ask_questions if host.nil?
      super
    end

    def ask_questions
      create_new_region_questions if action == :create
      clear_screen
      say("Database Configuration\n")
      ask_for_database_credentials(false)
    end
  end
end
end
