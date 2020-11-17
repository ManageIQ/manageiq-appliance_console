require 'active_support/core_ext/module/delegation'
require 'pathname'

module ManageIQ
  module ApplianceConsole
    class MessageConfiguration
      attr_reader :username, :password,
                  :miq_config_dir_path, :config_dir_path, :sample_config_dir_path,
                  :tools_log4_properties_path, :tools_log4_properties_sample_path,
                  :client_properties_path,
                  :keystore_dir_path, :truststore_path, :keystore_path,
                  :messaging_yaml_sample_path, :messaging_yaml_path

      BASE_DIR                          = "/opt/kafka".freeze
      LOGS_DIR                          = "#{BASE_DIR}/logs".freeze
      CONFIG_DIR                        = "#{BASE_DIR}/config".freeze
      SAMPLE_CONFIG_DIR                 = "#{BASE_DIR}/config-sample".freeze
      MIQ_CONFIG_DIR                    = "/var/www/miq/vmdb/config".freeze

      def initialize(options = {})
        @username, @password = nil

        @username = options[:username] || "admin"
        @password = options[:password]

        @miq_config_dir_path               = Pathname.new(MIQ_CONFIG_DIR)
        @config_dir_path                   = Pathname.new(CONFIG_DIR)
        @sample_config_dir_path            = Pathname.new(SAMPLE_CONFIG_DIR)

        @tools_log4_properties_path        = config_dir_path.join("tools-log4j.properties")
        @tools_log4_properties_sample_path = sample_config_dir_path.join("tools-log4j.properties")
        @client_properties_path            = config_dir_path.join("client.properties")

        @keystore_dir_path                 = config_dir_path.join("keystore")
        @truststore_path                   = keystore_dir_path.join("truststore.jks")
        @keystore_path                     = keystore_dir_path.join("keystore.jks")

        @messaging_yaml_sample_path        = miq_config_dir_path.join("messaging.kafka.yml")
        @messaging_yaml_path               = miq_config_dir_path.join("messaging.yml")
      end

      def create_tools_log_config
        say(__method__.to_s.tr("_", " ").titleize)

        FileUtils.cp(tools_log4_properties_sample_path, tools_log4_properties_path) unless file_found?(tools_log4_properties_path)
      end

      def create_client_properties
        say(__method__.to_s.tr("_", " ").titleize)

        content = <<~CLIENT_PROPERTIES
          ssl.truststore.location=#{truststore_path}
          ssl.truststore.password=#{password}

          sasl.mechanism=PLAIN
          security.protocol=SASL_SSL
          sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
            username=#{username} \\
            password=#{password} ;
        CLIENT_PROPERTIES

        File.write(client_properties_path, content) unless file_found?(client_properties_path)
      end

      def configure_messaging_yaml
        say(__method__.to_s.tr("_", " ").titleize)

        return if file_found?(messaging_yaml_path)

        messaging_yaml = YAML.load_file(messaging_yaml_sample_path)

        messaging_yaml["production"]["hostname"] = server_hostname
        messaging_yaml["production"]["port"] = 9093
        messaging_yaml["production"]["username"] = username
        messaging_yaml["production"]["password"] = password

        File.write(messaging_yaml_path, messaging_yaml.to_yaml)
      end

      def remove_installed_files
        say(__method__.to_s.tr("_", " ").titleize)

        installed_files.each { |f| FileUtils.rm_rf(f) if File.exist?(f) }
      end

      def valid_environment?
        return false unless installation_valid?

        if already_configured?
          return false unless agree("\nAlready configured on this Appliance, Un-Configure first? (Y/N): ")

          deactivate
          return false unless agree("\nProceed with Configuration? (Y/N): ")
        end
        true
      end

      def file_found?(path)
        return false unless File.exist?(path)

        say("\tWARNING: #{path} already exists. Taking no action.")
        true
      end

      def file_contains?(path, content)
        return false unless File.exist?(path)

        content.split("\n").each do |l|
          l.gsub!("/", "\\/")
          l.gsub!(/password=.*$/, "password=") # Remove the passord as it can have special characters that grep can not match.
          return false unless File.foreach(path).grep(/#{l}/).any?
        end

        say("Content already exists in #{path}. Taking no action.")
        true
      end

      #
      # Network validation
      #
      def host_reachable?(host, what)
        require 'net/ping'
        say("Checking connectivity to #{host} ... ")
        unless Net::Ping::External.new(host).ping
          say("Failed.\nCould not connect to #{host},")
          say("the #{what} must be reachable by name.")
          return false
        end
        say("Succeeded.")
        true
      end
    end
  end
end
