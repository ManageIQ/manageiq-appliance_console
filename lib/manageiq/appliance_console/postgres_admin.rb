require 'awesome_spawn'
require 'pathname'
require 'linux_admin'
require 'pg'

module ManageIQ
module ApplianceConsole
  class PostgresAdmin
    def self.data_directory
      Pathname.new(ENV.fetch("APPLIANCE_PG_DATA"))
    end

    def self.mount_point
      Pathname.new(ENV.fetch("APPLIANCE_PG_MOUNT_POINT"))
    end

    def self.template_directory
      Pathname.new(ENV.fetch("APPLIANCE_TEMPLATE_DIRECTORY"))
    end

    def self.service_name
      ENV.fetch("APPLIANCE_PG_SERVICE")
    end

    def self.package_name
      ENV.fetch('APPLIANCE_PG_PACKAGE_NAME')
    end

    # Unprivileged user to run postgresql
    def self.user
      "postgres".freeze
    end

    def self.group
      user
    end

    def self.logical_volume_name
      "lv_pg".freeze
    end

    def self.volume_group_name
      "vg_data".freeze
    end

    def self.database_disk_filesystem
      "xfs".freeze
    end

    def self.with_pg_connection(db_opts = {:user => user, :dbname => user})
      conn = PG.connect(db_opts)
      yield conn
    ensure
      conn.close if conn
    end

    def self.initialized?
      !Dir[data_directory.join("*")].empty?
    end

    def self.service_running?
      LinuxAdmin::Service.new(service_name).running?
    end

    def self.local_server_received_standby_signal?
      # Beginning with PostgreSQL 12, replication configuration has been integrated into the main PostgreSQL configuraton system and the conventional recovery.conf file is no longer valid.
      # see: https://repmgr.org/docs/current/release-5.0.html
      # https://www.2ndquadrant.com/en/blog/replication-configuration-changes-in-postgresql-12/
      # "standby.signal" – indicates the server should start up as a hot standby
      # If a standby is promoted, "standby.signal" is removed entirely (and not renamed as was the case with "recovery.conf", which became "recovery.done").
      data_directory.join("standby.signal").exist? || data_directory.join("recovery.conf").exist?
    end

    def self.local_server_status
      if service_running?
        "running (#{local_server_received_standby_signal? ? "standby" : "primary"})"
      elsif initialized?
        "initialized and stopped"
      else
        "not initialized"
      end
    end

    def self.logical_volume_path
      Pathname.new("/dev").join(volume_group_name, logical_volume_name)
    end

    def self.database_size(opts)
      result = run_command("psql", opts, :command => "SELECT pg_database_size('#{opts[:dbname]}');")
      result.match(/^\s+([0-9]+)\n/)[1].to_i
    end

    def self.prep_data_directory
      # initdb will fail if the database directory is not empty or not owned by the PostgresAdmin.user
      FileUtils.mkdir(PostgresAdmin.data_directory) unless Dir.exist?(PostgresAdmin.data_directory)
      FileUtils.chown_R(PostgresAdmin.user, PostgresAdmin.group, PostgresAdmin.data_directory)
      FileUtils.rm_rf(PostgresAdmin.data_directory.children.map(&:to_s))
    end

    PG_DUMP_MAGIC = "PGDMP".force_encoding(Encoding::BINARY).freeze
    def self.pg_dump_file?(file)
      File.open(file, "rb") { |f| f.readpartial(5) } == PG_DUMP_MAGIC
    end

    BASE_BACKUP_MAGIC = "\037\213".force_encoding(Encoding::BINARY).freeze # just the first 2 bits of gzip magic
    def self.base_backup_file?(file)
      File.open(file, "rb") { |f| f.readpartial(2) } == BASE_BACKUP_MAGIC
    end

    def self.backup(opts)
      backup_pg_compress(opts)
    end

    def self.restore(opts)
      file        = opts[:local_file]
      backup_type = opts.delete(:backup_type) || validate_backup_file_type(file)

      prepare_restore(backup_type, opts[:dbname])

      case backup_type
      when :pgdump     then restore_pg_dump(opts)
      when :basebackup then restore_pg_basebackup(file)
      else
        raise "#{file} is not a database backup"
      end
    end

    def self.restore_pg_basebackup(file)
      pg_service = LinuxAdmin::Service.new(service_name)

      pg_service.stop
      prep_data_directory

      require 'rubygems/package'

      # Using a Gem::Package instance for the #extract_tar_gz method, so we don't
      # have to re-write all of that logic.  Mostly making use of
      # `Gem::Package::TarReader` + `Zlib::GzipReader` that is already part of
      # rubygems/stdlib and integrated there.
      unpacker = Gem::Package.new("obviously_not_a_gem")
      File.open(file, IO::RDONLY | IO::NONBLOCK) do |backup_file|
        unpacker.extract_tar_gz(backup_file, data_directory.to_s)
      end

      FileUtils.chown_R(PostgresAdmin.user, PostgresAdmin.group, PostgresAdmin.data_directory)

      pg_service.start
      file
    end

    def self.backup_pg_dump(opts)
      opts = opts.dup
      dbname = opts.delete(:dbname)

      args = combine_command_args(opts, :format => "c", :file => opts[:local_file], nil => dbname)
      args = handle_multi_value_pg_dump_args!(opts, args)

      FileUtils.mkdir_p(File.dirname(opts.fetch(:local_file, "")))
      run_command_with_logging("pg_dump", opts, args)
      opts[:local_file]
    end

    def self.backup_pg_compress(opts)
      opts = opts.dup

      # discard dbname as pg_basebackup does not connect to a specific database
      opts.delete(:dbname)

      path = Pathname.new(opts.delete(:local_file))
      FileUtils.mkdir_p(path.dirname)

      # Build commandline from AwesomeSpawn
      args = {:z => nil, :format => "t", :wal_method => "fetch", :pgdata => "-"}
      cmd  = AwesomeSpawn.build_command_line("pg_basebackup", combine_command_args(opts, args))
      logger.info("MIQ(#{name}.#{__method__}) Running command... #{cmd}")

      # Run command in a separate thread
      read, write    = IO.pipe
      error_path     = Dir::Tmpname.create("") { |tmpname| tmpname }
      process_thread = Process.detach(Kernel.spawn(pg_env(opts), cmd, :out => write, :err => error_path))
      stream_reader  = Thread.new { IO.copy_stream(read, path) } # Copy output to path
      write.close

      # Wait for them to finish
      process_status = process_thread.value
      stream_reader.join
      read.close

      handle_error(cmd, process_status.exitstatus, error_path)
      path.to_s
    end

    def self.recreate_db(opts)
      dbname = opts[:dbname]
      opts = opts.merge(:dbname => 'postgres')
      run_command("psql", opts, :command => "DROP DATABASE IF EXISTS #{dbname}")
      run_command("psql", opts, :command => "CREATE DATABASE #{dbname} WITH OWNER = #{opts[:username] || 'root'} ENCODING = 'UTF8'")
    end

    def self.restore_pg_dump(opts)
      recreate_db(opts)
      args = { :verbose => nil, :exit_on_error => nil }

      if File.pipe?(opts[:local_file])
        cmd_args   = combine_command_args(opts, args)
        cmd        = AwesomeSpawn.build_command_line("pg_restore", cmd_args)
        error_path = Dir::Tmpname.create("") { |tmpname| tmpname }
        spawn_args = { :err => error_path, :in => [opts[:local_file].to_s, "rb"] }

        logger.info("MIQ(#{name}.#{__method__}) Running command... #{cmd}")
        process_thread = Process.detach(Kernel.spawn(pg_env(opts), cmd, spawn_args))
        process_status = process_thread.value

        handle_error(cmd, process_status.exitstatus, error_path)
      else
        args[nil] = opts[:local_file]
        run_command("pg_restore", opts, args)
      end
      opts[:local_file]
    end

    GC_DEFAULTS = {
      :analyze  => false,
      :full     => false,
      :verbose  => false,
      :table    => nil,
      :dbname   => nil,
      :username => nil,
      :reindex  => false
    }

    GC_AGGRESSIVE_DEFAULTS = {
      :analyze  => true,
      :full     => true,
      :verbose  => false,
      :table    => nil,
      :dbname   => nil,
      :username => nil,
      :reindex  => true
    }

    def self.gc(options = {})
      options = (options[:aggressive] ? GC_AGGRESSIVE_DEFAULTS : GC_DEFAULTS).merge(options)

      result = vacuum(options)
      logger.info("MIQ(#{name}.#{__method__}) Output... #{result}") if result.to_s.length > 0

      if options[:reindex]
        result = reindex(options)
        logger.info("MIQ(#{name}.#{__method__}) Output... #{result}") if result.to_s.length > 0
      end
    end

    def self.vacuum(opts)
      # TODO: Add a real exception here
      raise "Vacuum requires database" unless opts[:dbname]

      args = {}
      args[:analyze] = nil if opts[:analyze]
      args[:full]    = nil if opts[:full]
      args[:verbose] = nil if opts[:verbose]
      args[:table]   = opts[:table] if opts[:table]
      run_command("vacuumdb", opts, args)
    end

    def self.reindex(opts)
      args = {}
      args[:table] = opts[:table] if opts[:table]
      run_command("reindexdb", opts, args)
    end

    def self.run_command(cmd_str, opts, args)
      run_command_with_logging(cmd_str, opts, combine_command_args(opts, args))
    end

    def self.run_command_with_logging(cmd_str, opts, params = {})
      logger.info("MIQ(#{name}.#{__method__}) Running command... #{AwesomeSpawn.build_command_line(cmd_str, params)}")
      AwesomeSpawn.run!(cmd_str, :params => params, :env => pg_env(opts)).output
    end

    class << self
      # Temporary alias due to manageiq core stubbing this method
      alias runcmd_with_logging run_command_with_logging
    end

    private_class_method def self.combine_command_args(opts, args)
      default_args            = {:no_password => nil}
      default_args[:dbname]   = opts[:dbname]   if opts[:dbname]
      default_args[:username] = opts[:username] if opts[:username]
      default_args[:host]     = opts[:hostname] if opts[:hostname]
      default_args[:port]     = opts[:port]     if opts[:port]
      default_args.merge(args)
    end

    private_class_method def self.logger
      ManageIQ::ApplianceConsole.logger
    end

    private_class_method def self.pg_env(opts)
      {
        "PGUSER"     => opts[:username],
        "PGPASSWORD" => opts[:password]
      }.delete_blanks
    end
    # rubocop:disable Style/SymbolArray
    PG_DUMP_MULTI_VALUE_ARGS = [
      :t, :table,  :T, :exclude_table,  :"exclude-table", :exclude_table_data, :"exclude-table-data",
      :n, :schema, :N, :exclude_schema, :"exclude-schema"
    ].freeze
    # rubocop:enable Style/SymbolArray
    #
    # NOTE:  Potentially mutates opts hash (args becomes new array and not
    # mutated by this method)
    private_class_method def self.handle_multi_value_pg_dump_args!(opts, args)
      if opts.keys.any? { |key| PG_DUMP_MULTI_VALUE_ARGS.include?(key) }
        args = args.to_a
        PG_DUMP_MULTI_VALUE_ARGS.each do |table_key|
          next unless opts.key?(table_key)
          table_val = opts.delete(table_key)
          args += Array.wrap(table_val).map! { |v| [table_key, v] }
        end
      end
      args
    end

    private_class_method def self.handle_error(cmd, exit_status, error_path)
      if exit_status != 0
        result = AwesomeSpawn::CommandResult.new(cmd, "", File.read(error_path), exit_status)
        message = AwesomeSpawn::CommandResultError.default_message(cmd, exit_status)
        logger.error("AwesomeSpawn: #{message}")
        logger.error("AwesomeSpawn: #{result.error}")
        raise AwesomeSpawn::CommandResultError.new(message, result)
      end
    ensure
      File.delete(error_path) if File.exist?(error_path)
    end

    private_class_method def self.prepare_restore(backup_type, dbname)
      if application_connections?
        message = "Database restore failed. Shut down all evmserverd processes before attempting a database restore"
        ManageIQ::ApplianceConsole.logger.error(message)
        raise message
      end

      disable_replication(dbname)

      conn_count = connection_count(backup_type, dbname)
      if conn_count > 1
        message = "Database restore failed. #{conn_count - 1} connections remain to the database."
        ManageIQ::ApplianceConsole.logger.error(message)
        raise message
      end
    end

    private_class_method def self.application_connections?
      result = [{"count" => 0}]

      with_pg_connection do |conn|
        result = conn.exec("SELECT COUNT(pid) FROM pg_stat_activity WHERE application_name LIKE '%MIQ%'")
      end

      result[0]["count"].to_i > 0
    end

    private_class_method def self.disable_replication(dbname)
      require 'pg/logical_replication'

      with_pg_connection do |conn|
        pglogical = PG::LogicalReplication::Client.new(conn)

        if pglogical.subscriber?
          pglogical.subcriptions(dbname).each do |subscriber|
            sub_id = subscriber["subscription_name"]
            begin
              pglogical.drop_subscription(sub_id, true)
            rescue PG::InternalError => e
              raise unless e.message.include?("could not connect to publisher")
              raise unless e.message.match?(/replication slot .* does not exist/)

              pglogical.disable_subscription(sub_id).check
              pglogical.alter_subscription_options(sub_id, "slot_name" => "NONE")
              pglogical.drop_subscription(sub_id, true)
            end
          end
        elsif pglogical.publishes?('miq')
          pglogical.drop_publication('miq')
        end
      end
    end

    private_class_method def self.connection_count(backup_type, dbname)
      result = nil

      with_pg_connection do |conn|
        query  = "SELECT COUNT(pid) FROM pg_stat_activity"
        query << " WHERE backend_type = 'client backend'" if backup_type == :basebackup
        query << " WHERE datname = '#{dbname}'"           if backup_type == :pgdump
        result = conn.exec(query)
      end

      result[0]["count"].to_i
    end

    private_class_method def self.validate_backup_file_type(file)
      if base_backup_file?(file)
        :basebackup
      elsif pg_dump_file?(file)
        :pgdump
      else
        message = "#{filename} is not in a recognized database backup format"
        ManageIQ::ApplianceConsole.error(message)
        raise message
      end
    end
  end
end
end
