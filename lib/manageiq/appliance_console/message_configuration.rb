require 'active_support/core_ext/module/delegation'
require 'pathname'

module ManageIQ
  module ApplianceConsole
    class MessageConfiguration
      attr_reader :username, :password, :secure,
                  :server_host, :server_port, :server_host_is_ipaddr,
                  :miq_config_dir_path, :config_dir_path, :sample_config_dir_path,
                  :client_properties_path,
                  :keystore_dir_path, :truststore_path, :keystore_path,
                  :messaging_yaml_sample_path, :messaging_yaml_path,
                  :ca_cert_path

      BASE_DIR                          = "/opt/kafka".freeze
      LOGS_DIR                          = "#{BASE_DIR}/logs".freeze
      CONFIG_DIR                        = "#{BASE_DIR}/config".freeze
      SAMPLE_CONFIG_DIR                 = "#{BASE_DIR}/config-sample".freeze
      MIQ_CONFIG_DIR                    = ManageIQ::ApplianceConsole::RAILS_ROOT.join("config").freeze

      def initialize(options = {})
        @server_port = options[:server_port] || 9093
        @username = options[:username] || "admin"
        @password = options[:password]

        @miq_config_dir_path               = Pathname.new(MIQ_CONFIG_DIR)
        @config_dir_path                   = Pathname.new(CONFIG_DIR)
        @sample_config_dir_path            = Pathname.new(SAMPLE_CONFIG_DIR)

        @client_properties_path            = config_dir_path.join("client.properties")
        @keystore_dir_path                 = config_dir_path.join("keystore")
        @truststore_path                   = keystore_dir_path.join("truststore.jks")
        @keystore_path                     = keystore_dir_path.join("keystore.jks")

        @messaging_yaml_sample_path        = miq_config_dir_path.join("messaging.kafka.yml")
        @messaging_yaml_path               = miq_config_dir_path.join("messaging.yml")
        @ca_cert_path                      = keystore_dir_path.join("ca-cert")
      end

      def already_configured?
        installed_file_found = false
        installed_files.each do |f|
          if File.exist?(f)
            installed_file_found = true
            say("Installed file #{f} found.")
          end
        end
        installed_file_found
      end

      def ask_questions
        return false unless valid_environment?

        ask_for_parameters
        show_parameters
        return false unless agree("\nProceed? (Y/N): ")

        return false unless host_reachable?(server_host, "Message Server Host:")

        true
      end

      def create_client_properties
        say(__method__.to_s.tr("_", " ").titleize)

        return if file_found?(client_properties_path)

        algorithm = server_host_is_ipaddr? ? "" : "HTTPS"
        content = secure? ? secure_client_properties_content(algorithm) : unsecure_client_properties_content(algorithm)

        File.write(client_properties_path, content)
      end

      def secure_client_properties_content(algorithm)
        <<~CLIENT_PROPERTIES
          ssl.endpoint.identification.algorithm=#{algorithm}
          ssl.truststore.location=#{truststore_path}
          ssl.truststore.password=#{password}

          sasl.mechanism=PLAIN
          security.protocol=SASL_SSL
          sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
            username=#{username} \\
            password=#{password} ;
        CLIENT_PROPERTIES
      end

      def unsecure_client_properties_content(algorithm)
        <<~CLIENT_PROPERTIES
          ssl.endpoint.identification.algorithm=#{algorithm}
          sasl.mechanism=PLAIN
          security.protocol=PLAINTEXT
          sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
            username=#{username} \\
            password=#{password} ;
        CLIENT_PROPERTIES
      end

      def configure_messaging_yaml
        say(__method__.to_s.tr("_", " ").titleize)

        return if file_found?(messaging_yaml_path)

        messaging_yaml = YAML.load_file(messaging_yaml_sample_path)

        messaging_yaml["production"].delete("username")
        messaging_yaml["production"].delete("password")

        messaging_yaml["production"]["hostname"]          = server_host
        messaging_yaml["production"]["port"]              = server_port
        messaging_yaml["production"]["sasl.mechanism"]    = "PLAIN"
        messaging_yaml["production"]["sasl.username"]     = username
        messaging_yaml["production"]["sasl.password"]     = ManageIQ::Password.try_encrypt(password)

        if secure?
          messaging_yaml["production"]["security.protocol"] = "SASL_SSL"
          messaging_yaml["production"]["ssl.ca.location"]   = ca_cert_path.to_path
        else
          messaging_yaml["production"]["security.protocol"] = "PLAINTEXT"
        end

        File.write(messaging_yaml_path, messaging_yaml.to_yaml)
      end

      def remove_installed_files
        say(__method__.to_s.tr("_", " ").titleize)

        installed_files.each { |f| FileUtils.rm_rf(f) }
      end

      def valid_environment?
        if already_configured?
          deactivate if agree("\nAlready configured on this Appliance, Un-Configure first? (Y/N): ")
          return false unless agree("\nProceed with Configuration? (Y/N): ")
        end
        true
      end

      def file_found?(path)
        return false unless File.exist?(path)

        say("\tWARNING: #{path} already exists. Taking no action.")
        true
      end

      def files_found?(path_list)
        return false unless path_list.all? { |path| File.exist?(path) }

        path_list.each { |path| file_found?(path) }
        true
      end

      def file_contains?(path, content)
        return false unless File.exist?(path)

        content.split("\n").each do |l|
          l.gsub!("/", "\\/")
          l.gsub!(/password=.*$/, "password=") # Remove the password as it can have special characters that grep can not match.
          return false unless File.foreach(path).grep(/#{l}/).any?
        end

        say("Content already exists in #{path}. Taking no action.")
        true
      end

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

      def configure_messaging_type(value)
        say(__method__.to_s.tr("_", " ").titleize)

        result = ManageIQ::ApplianceConsole::Utilities.rake_run("evm:settings:set", ["/prototype/messaging_type=#{value}"])
        raise parse_errors(result).join(', ') if result.failure?
      end

      def restart_evmserverd
        say("Restart evmserverd if it is running...")
        evmserverd_service = LinuxAdmin::Service.new("evmserverd")
        evmserverd_service.restart if evmserverd_service.running?
      end

      def deactivate
        @secure = nil
        @server_host_is_ipaddr = nil
        configure_messaging_type("miq_queue") # Settings.prototype.messaging_type = 'miq_queue'
        restart_evmserverd
        remove_installed_files
      end

      def secure?
        @secure ||= server_port == 9_093
      end

      def server_host_is_ipaddr?
        @server_host_is_ipaddr ||= server_host.ipaddress?
      end
    end
  end
end
