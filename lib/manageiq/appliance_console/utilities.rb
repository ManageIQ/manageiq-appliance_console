# TODO: add appropriate requires instead of depending on appliance_console.rb.
# TODO: Further refactor these unrelated methods.
require "manageiq/appliance_console/postgres_admin"
require "awesome_spawn"

module ManageIQ
module ApplianceConsole
  module Utilities
    def self.rake(task, params, env = {})
      rake_run(task, params, env).success?
    end

    def self.rake_run(task, params, env = {})
      result = AwesomeSpawn.run("rake #{task}", :chdir => ManageIQ::ApplianceConsole::RAILS_ROOT, :params => params, :env => env)
      ManageIQ::ApplianceConsole.logger.error(result.error) if result.failure?
      result
    end

    def self.rake_run!(task, params, env = {})
      result = rake_run(task, params, env)
      if result.failure?
        parsed_errors = result.error.split("\n").select { |line| line.match?(/^error: /i) }.join(', ')
        raise parsed_errors
      end

      result
    end

    def self.db_connections
      # TODO: this is impossible to test right now because we need to shell out and run our rails app which isn't a direct dependency here.
      # We have the settings from the database_configuration, so we should pass them here and simplify this and make it testable.
      # Basically, we're doing a lot of work to run this 1 query:
      #   psql -U username -h host postgres -c "select count(*) from pg_stat_activity where datname = 'vmdb_production';"
      # We shouldn't need to subtract our 1 "connection" in "bail_if_db_connections" if we connect to the postgres db.
      code   = [
        "database ||= ActiveRecord::Base.configurations.configs_for(:env_name => Rails.env).first.database",
        "conn = ActiveRecord::Base.connection",
        "exit conn.client_connections.count { |c| c['database'] == database }"
      ]
      result = AwesomeSpawn.run("bin/rails runner",
                                :params => [code.join("; ")],
                                :chdir  => ManageIQ::ApplianceConsole::RAILS_ROOT
                               )
      Integer(result.exit_status)
    end

    def self.bail_if_db_connections(message)
      say("Checking for connections to the database...\n\n")
      if (conns = ManageIQ::ApplianceConsole::Utilities.db_connections - 1) > 0
        say("Warning: There are #{conns} existing connections to the database #{message}.\n\n")
        press_any_key
        raise MiqSignalError
      end
    end

    def self.db_region
      result = AwesomeSpawn.run(
        "bin/rails runner",
        :params => ["puts ApplicationRecord.my_region_number"],
        :chdir  => ManageIQ::ApplianceConsole::RAILS_ROOT
      )

      if result.failure?
        logger = ManageIQ::ApplianceConsole.logger
        logger.error "db_region: Failed to detect region_number"
        logger.error "Output: #{result.output.inspect}" unless result.output.blank?
        logger.error "Error:  #{result.error.inspect}"  unless result.error.blank?
        return
      end

      result.output.strip
    end

    def self.pg_status
      LinuxAdmin::Service.new(PostgresAdmin.service_name).running? ? "running" : "not running"
    end

    def self.test_network
      require 'net/ping'
      say("Test Network Configuration\n\n")
      while (h = ask_for_ip_or_hostname_or_none("hostname, ip address, or none to continue").presence)
        say("  " + h + ': ' + (Net::Ping::External.new(h).ping ? 'Success!' : 'Failure, Check network settings and IP address or hostname provided.'))
      end
    end

    def self.disk_usage(file = nil)
      file_arg = file
      file_arg = "-l" if file.nil? || file == ""

      unless file_arg == "-l" || File.exist?(file)
        raise "file #{file} does not exist"
      end

      # Collect bytes
      result = AwesomeSpawn.run!("df", :params => ["-T", "-P", file_arg]).output.lines.each_with_object([]) do |line, array|
        lArray = line.strip.split(" ")
        next if lArray.length != 7
        fsname, type, total, used, free, used_percentage, mount_point = lArray
        next unless total =~ /[0-9]+/
        next if array.detect { |hh| hh[:filesystem] == fsname }

        array << {
          :filesystem         => fsname,
          :type               => type,
          :total_bytes        => total.to_i * 1024,
          :used_bytes         => used.to_i * 1024,
          :available_bytes    => free.to_i * 1024,
          :used_bytes_percent => used_percentage.chomp("%").to_i,
          :mount_point        => mount_point,
        }
      end

      # Collect inodes
      AwesomeSpawn.run!("df", :params => ["-T", "-P", "-i", file_arg]).output.lines.each do |line|
        lArray = line.strip.split(" ")
        next if lArray.length != 7
        fsname, _type, total, used, free, used_percentage, _mount_point = lArray
        next unless total =~ /[0-9]+/
        h = result.detect { |hh| hh[:filesystem] == fsname }
        next if h.nil?

        h[:total_inodes]        = total.to_i
        h[:used_inodes]         = used.to_i
        h[:available_inodes]    = free.to_i
        h[:used_inodes_percent] = used_percentage.chomp("%").to_i
      end
      result
    end
  end
end
end
