require 'active_record'
require 'active_support/core_ext'
require 'linux_admin'
require 'manageiq-password'
require 'pathname'
require 'fileutils'

require_relative './manageiq_user_mixin'

module ManageIQ
module ApplianceConsole
  class DatabaseConfiguration
    include ManageIQ::ApplianceConsole::ManageiqUserMixin

    attr_accessor :adapter, :host, :username, :database, :port, :region
    attr_reader :password

    class ModelWithNoBackingTable < ActiveRecord::Base
    end

    DB_YML      = ManageIQ::ApplianceConsole::RAILS_ROOT.join("config/database.yml")
    DB_YML_TMPL = ManageIQ::ApplianceConsole::RAILS_ROOT.join("config/database.pg.yml")

    CREATE_REGION_AGREE = "WARNING: Creating a database region will destroy any existing data and cannot be undone.\n\nAre you sure you want to continue? (Y/N):".freeze
    FAILED_WITH_ERROR_HYPHEN = "failed with error -".freeze

    # PG 9.2 bigint max 9223372036854775807 / ArRegion::DEFAULT_RAILS_SEQUENCE_FACTOR = 9223372
    # http://www.postgresql.org/docs/9.2/static/datatype-numeric.html
    # 9223372 won't be a full region though, so we're not including it.
    # TODO: This information should be shared outside of appliance console code and MiqRegion.
    REGION_RANGE = 0..9223371
    DEFAULT_PORT = 5432

    include ManageIQ::ApplianceConsole::Logging

    def initialize(hash = {})
      initialize_from_hash(hash)
      @adapter ||= "postgresql"
      # introduced by Logging
      self.interactive = true unless hash.key?(:interactive)
    end

    def run_interactive
      ask_questions

      clear_screen
      say "Activating the configuration using the following settings...\n#{friendly_inspect}\n"

      raise MiqSignalError unless activate

      post_activation
      say("\nConfiguration activated successfully.\n")
    rescue RuntimeError => e
      puts "Configuration failed#{": " + e.message unless e.class == MiqSignalError}"
      press_any_key
      raise MiqSignalError
    end

    def local?
      host.blank? || host.in?(%w(localhost 127.0.0.1))
    end

    def password=(value)
      @password = ManageIQ::Password.try_decrypt(value)
    end

    def activate
      return false unless validated

      original = self.class.current
      success  = false

      begin
        save
        success = create_or_join_region
        validate_encryption_key!
      rescue
        success = false
      ensure
        save(original) unless success
      end
    end

    def create_or_join_region
      region ? create_region : join_region
    end

    def create_region
      hint = "Please stop the EVM server process on all appliances in the region"
      ManageIQ::ApplianceConsole::Utilities.bail_if_db_connections("preventing the setup of a database region.\n#{hint}")
      log_and_feedback(__method__) do
        ManageIQ::ApplianceConsole::Utilities.rake("evm:db:region", {}, {'REGION' => region.to_s, 'VERBOSE' => 'false'})
      end
    end

    def join_region
      ManageIQ::ApplianceConsole::Utilities.rake("evm:join_region", {})
    end

    def reset_region
      say("Warning: RESETTING A DATABASE WILL DESTROY ANY EXISTING DATA AND CANNOT BE UNDONE.\n\n")
      raise MiqSignalError unless are_you_sure?("reset the configured database")

      create_new_region_questions(false)
      ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = "1"
      create_region
    ensure
      ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = nil
    end

    def create_new_region_questions(warn = true)
      clear_screen
      say("\n\nNote: Creating a new database region requires an empty database.") if warn
      say("Each database region number must be unique.\n")
      self.region = ask_for_integer("database region number", REGION_RANGE)
      raise MiqSignalError if warn && !agree(CREATE_REGION_AGREE)
    end

    def ask_for_database_credentials(password_twice = true)
      self.host     = ask_for_ip_or_hostname("database hostname or IP address", host) if host.blank? || !local?
      self.port     = ask_for_integer("port number", nil, port) unless local?
      self.database = just_ask("name of the database on #{host}", database) unless local?
      self.username = just_ask("username", username) unless local?
      count = 0
      loop do
        password1 = ask_for_password("database password on #{host}", password)
        # if they took the default, just bail
        break if (password1 == password)

        if password1.strip.length == 0
          say("\nPassword can not be empty, please try again")
          next
        end
        if password_twice
          password2 = ask_for_password("database password again")
          if password1 == password2
            self.password = password1
            break
          elsif count > 0 # only reprompt password once
            raise "passwords did not match"
          else
            count += 1
            say("\nThe passwords did not match, please try again")
          end
        else
          self.password = password1
          break
        end
      end
    end

    def friendly_inspect
      output = <<-FRIENDLY
Host:     #{host}
Username: #{username}
Database: #{database}
FRIENDLY
      output << "Port:     #{port}\n" if port
      output << "Region:   #{region}\n" if region
      output
    end

    def settings_hash
      {
        'adapter'  => 'postgresql',
        'host'     => local? ? "localhost" : host,
        'port'     => port,
        'username' => username,
        'password' => password.presence,
        'database' => database
      }
    end

    # merge all the non specified setings
    # for all the basic attributes, overwrite from this object (including blank values)
    def merged_settings
      merged = self.class.current
      settings_hash.each do |k, v|
        if v.present?
          merged['production'][k] = v
        else
          merged['production'].delete(k)
        end
      end
      merged
    end

    def save(settings = nil)
      settings ||= merged_settings
      settings = self.class.encrypt_password(settings)
      do_save(settings)
    end

    def self.encrypt_password(settings)
      encrypt_decrypt_password(settings) { |pass| ManageIQ::Password.try_encrypt(pass) }
    end

    def self.decrypt_password(settings)
      encrypt_decrypt_password(settings) { |pass| ManageIQ::Password.try_decrypt(pass) }
    end

    def self.current
      decrypt_password(load_current)
    end

    def self.database_yml_configured?
      File.exist?(DB_YML) && File.exist?(KEY_FILE)
    end

    def self.database_host
      database_yml_configured? ? current[rails_env]['host'] || "localhost" : nil
    end

    def self.database_name
      database_yml_configured? ? current[rails_env]['database'] : nil
    end

    def self.region
      database_yml_configured? ? ManageIQ::ApplianceConsole::Utilities.db_region : nil
    end

    def validated
      !!validate!
    rescue => err
      log_error(__method__, err.message)
      say_error(__method__, err.message)
      false
    end

    def validate!
      pool = ModelWithNoBackingTable.establish_connection(settings_hash.delete_if { |_n, v| v.blank? })
      begin
        pool.connection
      ensure
        ModelWithNoBackingTable.remove_connection
      end
    end

    def start_evm
      pid = fork do
        begin
          EvmServer.start(:enable => true)
        rescue => e
          logger.error("Failed to enable and start evmserverd service: #{e.message}")
          logger.error(e.backtrace.join("\n"))
        end
      end
      Process.detach(pid)
    end

    private

    def self.rails_env
      ENV["RAILS_ENV"] || "development"
    end
    private_class_method :rails_env

    def self.encrypt_decrypt_password(settings)
      new_settings = {}
      settings.each_key { |section| new_settings[section] = settings[section].dup }
      pass = new_settings["production"]["password"]
      new_settings["production"]["password"] = yield(pass) if pass
      new_settings
    end

    def self.load_current
      require 'yaml'
      unless File.exist?(DB_YML)
        require 'fileutils'
        FileUtils.cp(DB_YML_TMPL, DB_YML) if File.exist?(DB_YML_TMPL)
      end
      YAML.load_file(DB_YML)
    end

    def validate_encryption_key!
      raise "Encryption key invalid" unless ManageIQ::ApplianceConsole::Utilities.rake("evm:validate_encryption_key", {})
      true
    end

    def do_save(settings)
      require 'yaml'
      File.open(DB_YML, "w") do |f|
        f.write(YAML.dump(settings))
        f.chown(manageiq_uid, manageiq_gid)
      end
    end

    def initialize_from_hash(hash)
      hash.each do |k, v|
        next if v.nil?
        setter = "#{k}="
        if self.respond_to?(setter)
          public_send(setter, v)
        else
          raise ArgumentError, "Invalid argument: #{k}"
        end
      end
    end
  end
end
end
