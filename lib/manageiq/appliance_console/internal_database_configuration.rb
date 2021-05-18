require "pathname"
require "manageiq/appliance_console/postgres_admin"
require "linux_admin"

module ManageIQ
module ApplianceConsole
  class InternalDatabaseConfiguration < DatabaseConfiguration
    attr_accessor :disk, :run_as_evm_server

    DEDICATED_DB_SHARED_BUFFERS = "'1GB'".freeze
    SHARED_DB_SHARED_BUFFERS = "'128MB'".freeze

    def self.postgres_dir
      PostgresAdmin.data_directory.relative_path_from(Pathname.new("/"))
    end

    def self.postgresql_template
      PostgresAdmin.template_directory.join(postgres_dir)
    end

    def initialize(hash = {})
      set_defaults
      super
    end

    def set_defaults
      self.host              = 'localhost'
      self.username          = "root"
      self.database          = "vmdb_production"
      self.run_as_evm_server = true
    end

    def activate
      if PostgresAdmin.initialized?
        say(<<-EOF.gsub!(/^\s+/, ""))
          An internal database already exists.
          Choose "Reset Configured Database" to reset the existing installation
          EOF
        return false
      end
      initialize_postgresql_disk if disk
      initialize_postgresql
      run_as_evm_server ? (return super) : save
      true
    end

    def ask_questions
      choose_disk
      check_disk_is_mount_point
      self.run_as_evm_server = !ask_yn?(<<-EOS.gsub!(/^ +/m, ""), "N")

        Should this appliance run as a standalone database server?

        NOTE:
        * The #{I18n.t("product.name")} application will not be running.
        * This is required when using highly available database deployments.
        * CAUTION: This is not reversible.

      EOS
      # TODO: Assume we want to create a region for a new internal database disk
      # until we allow for the internal selection against an already initialized disk.
      create_new_region_questions(false) if run_as_evm_server
      ask_for_database_credentials
    end

    def choose_disk
      @disk = ask_for_disk("database disk", false, true)
    end

    def check_disk_is_mount_point
      error_message = "Internal databases require a volume mounted at #{mount_point}. Please add an unpartitioned disk and try again."
      raise error_message unless disk || pg_mount_point?
    end

    def initialize_postgresql_disk
      log_and_feedback(__method__) do
        LogicalVolumeManagement.new(:disk                => disk,
                                    :mount_point         => mount_point,
                                    :name                => "pg",
                                    :volume_group_name   => PostgresAdmin.volume_group_name,
                                    :filesystem_type     => PostgresAdmin.database_disk_filesystem,
                                    :logical_volume_path => PostgresAdmin.logical_volume_path).setup
      end

      # if we mounted the disk onto the postgres user's home directory, fix the permissions
      if mount_point.to_s == "/var/lib/pgsql"
        FileUtils.chown(PostgresAdmin.user, PostgresAdmin.group, "/var/lib/pgsql")
        FileUtils.chmod(0o700, "/var/lib/pgsql")
      end
    end

    def initialize_postgresql
      log_and_feedback(__method__) do
        PostgresAdmin.prep_data_directory
        run_initdb
        configure_ssl
        relabel_postgresql_dir
        configure_postgres
        start_postgres
        create_postgres_root_user
        create_postgres_database
        apply_initial_configuration
      end
    end

    def configure_postgres
      copy_template "postgresql.conf"
      copy_template "pg_hba.conf"
      copy_template "pg_ident.conf"
    end

    def post_activation
      start_evm if run_as_evm_server
    end

    private

    def mount_point
      PostgresAdmin.mount_point
    end

    def copy_template(src)
      FileUtils.cp(self.class.postgresql_template.join(src), PostgresAdmin.data_directory)
    end

    def pg_mount_point?
      LinuxAdmin::LogicalVolume.mount_point_exists?(mount_point.to_s)
    end

    def run_initdb
      AwesomeSpawn.run!("postgresql-setup", :params => {:initdb => nil, :unit => PostgresAdmin.service_name})
    end

    def start_postgres
      LinuxAdmin::Service.new(PostgresAdmin.service_name).enable.start
      block_until_postgres_accepts_connections
    end

    def restart_postgres
      LinuxAdmin::Service.new(PostgresAdmin.service_name).restart
      block_until_postgres_accepts_connections
    end

    def block_until_postgres_accepts_connections
      loop do
        break if AwesomeSpawn.run("psql -U postgres -c 'select 1'").success?
      end
    end

    def create_postgres_root_user
      PostgresAdmin.with_pg_connection do |conn|
        esc_pass = conn.escape_string(password)
        conn.exec("CREATE ROLE #{username} WITH LOGIN CREATEDB SUPERUSER PASSWORD '#{esc_pass}'")
      end
    end

    def create_postgres_database
      PostgresAdmin.with_pg_connection do |conn|
        conn.exec("CREATE DATABASE #{database} OWNER #{username} ENCODING 'utf8'")
      end
    end

    def relabel_postgresql_dir
      AwesomeSpawn.run!("/sbin/restorecon -R -v #{mount_point}")
    end

    def apply_initial_configuration
      shared_buffers = run_as_evm_server ? SHARED_DB_SHARED_BUFFERS : DEDICATED_DB_SHARED_BUFFERS
      PostgresAdmin.with_pg_connection { |conn| conn.exec("ALTER SYSTEM SET shared_buffers TO #{shared_buffers}") }

      restart_postgres
    end

    def configure_ssl
      cert_file = PostgresAdmin.data_directory.join("server.crt").to_s
      key_file  = PostgresAdmin.data_directory.join("server.key").to_s
      AwesomeSpawn.run!("/usr/bin/generate_miq_server_cert.sh", :env => {"NEW_CERT_FILE" => cert_file, "NEW_KEY_FILE"  => key_file})

      FileUtils.chown("postgres", "postgres", cert_file)
      FileUtils.chown("postgres", "postgres", key_file)
      FileUtils.chmod(0644, cert_file)
      FileUtils.chmod(0600, key_file)
    end
  end
end
end
