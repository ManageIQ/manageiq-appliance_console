require "awesome_spawn"
require "fileutils"
require "linux_admin"
require "manageiq/appliance_console/message_configuration"

module ManageIQ
  module ApplianceConsole
    class MessageServerConfiguration < MessageConfiguration
      attr_reader :server_hostname, :jaas_config_path,
                  :server_properties_path, :server_properties_sample_path,
                  :ca_cert_path, :ca_key_path, :cert_file_path, :cert_signed_path,
                  :installed_files

      def initialize(options = {})
        super(options)

        @server_hostname = my_hostname

        @jaas_config_path                  = config_dir_path.join("kafka_server_jaas.conf")
        @server_properties_path            = config_dir_path.join("server.properties")
        @server_properties_sample_path     = sample_config_dir_path.join("server.properties")

        @ca_cert_path                      = keystore_dir_path.join("ca-cert")
        @ca_key_path                       = keystore_dir_path.join("ca-key")
        @cert_file_path                    = keystore_dir_path.join("cert-file")
        @cert_signed_path                  = keystore_dir_path.join("cert-signed")

        @installed_files = [tools_log4_properties_path, jaas_config_path,
                            client_properties_path, server_properties_path,
                            messaging_yaml_path, LOGS_DIR, keystore_dir_path]
      end

      def ask_questions
        return false unless valid_environment?

        ask_for_parameters
        show_parameters
        return false unless agree("\nProceed? (Y/N): ")
        return false unless host_reachable?(server_hostname, "Message Server")

        true
      end

      def activate
        begin
          create_tools_log_config      # Create the tools log configuration file
          create_jaas_config           # Create the message server jaas config file
          create_client_properties     # Create the client.properties config
          create_logs_directory        # Create the logs directory:
          configure_firewall           # Open the firewall for message port 9092
          configure_keystore           # Populate the Java Keystore
          create_server_properties     # Update the /opt/message/config/server.properties
          configure_messaging_yaml     # Set up the local message client in case EVM is actually running on this, Message Server
        rescue AwesomeSpawn::CommandResultError => e
          say(e.result.output)
          say(e.result.error)
          say("")
          say("Failed to Configure the Message Server- #{e}")
          return false
        rescue => e
          say("Failed to Configure the Message Server- #{e}")
          return false
        end
        true
      end

      def post_activation
        say("Starting zookeeper and configure it to start on reboots ...")
        LinuxAdmin::Service.new("zookeeper").start.enable

        say("Starting kafka and configure it to start on reboots ...")
        LinuxAdmin::Service.new("kafka").start.enable
      end

      def ask_for_parameters
        say("\nMessage Server Parameters:\n\n")

        @username  = ask_for_string("Message Key Username", username)
        @password  = ask_for_password("Message Key Password")
      end

      def show_parameters
        say("\nMessage Server Configuration:\n")
        say("Message Server Details:\n")
        say("  Message Server Hostname:   #{server_hostname}\n")
        say("  Message Key Username:      #{username}\n")
      end

      private

      def my_hostname
        LinuxAdmin::Hosts.new.hostname
      end

      def create_jaas_config
        say(__method__.to_s.tr("_", " ").titleize)

        content = <<~JAAS
          KafkaServer {
            org.apache.kafka.common.security.plain.PlainLoginModule required
            username=#{username}
            password=#{password}
            user_admin=#{password} ;
          };
        JAAS

        File.write(jaas_config_path, content) unless file_found?(jaas_config_path)
      end

      def create_logs_directory
        say(__method__.to_s.tr("_", " ").titleize)

        return true if file_found?(LOGS_DIR)

        FileUtils.mkdir_p(LOGS_DIR)
        FileUtils.chmod(0o755, LOGS_DIR)
        FileUtils.chown("kafka", "kafka", LOGS_DIR)
      end

      def configure_firewall
        say(__method__.to_s.tr("_", " ").titleize)

        AwesomeSpawn.run!("firewall-cmd --add-port=9092/tcp --permanent") # insecure
        AwesomeSpawn.run!("firewall-cmd --add-port=9093/tcp --permanent") # secure
        AwesomeSpawn.run!("firewall-cmd --reload")
      end

      def configure_keystore
        say(__method__.to_s.tr("_", " ").titleize)

        return true if file_found?(keystore_dir_path)

        FileUtils.mkdir_p(keystore_dir_path)
        FileUtils.chmod(0o755, keystore_dir_path)

        # Generte a Java keystore and key pair, creating keystore.jks
        AwesomeSpawn.run!("keytool -keystore #{keystore_path} -alias localhost -validity 10000 -genkey -keyalg RSA -storepass #{password} -keypass #{password} -dname \"cn=#{server_hostname}\" ")

        # Use openssl to create a new CA cert, creating ca-cert and ca-key
        AwesomeSpawn.run!("PASSWORD='#{password}' openssl req -new -x509 -keyout #{ca_key_path} -out #{ca_cert_path} -days 10000 -passout 'env:PASSWORD' -subj '/CN=something'")

        # Import the CA cert into the trust store, creating truststore.jks
        AwesomeSpawn.run!("keytool -keystore #{truststore_path} -alias CARoot -import -file #{ca_cert_path} -storepass #{password} -noprompt")

        # Generate a certificate signing request (CSR) for an existing Java keystore, creating cert-file
        AwesomeSpawn.run!("keytool -keystore #{keystore_path} -alias localhost -certreq -file #{cert_file_path} -storepass #{password} ")

        # Use openssl to sign the certificate with the "CA" certificate, creating ca-cert.srl and cert-signed
        AwesomeSpawn.run!("PASSWORD='#{password}' openssl x509 -req -CA #{ca_cert_path} -CAkey #{ca_key_path} -in #{cert_file_path} -out #{cert_signed_path} -days 10000 -CAcreateserial -passin 'env:PASSWORD'")

        # Import a root or intermediate CA certificate to an existing Java keystore, updating keystore.jks
        AwesomeSpawn.run!("keytool -keystore #{keystore_path} -alias CARoot -import -file #{ca_cert_path} -storepass #{password} -noprompt")

        # Import a signed primary certificate to an existing Java keystore, updating keystore.jks
        AwesomeSpawn.run!("keytool -keystore #{keystore_path} -alias localhost -import -file #{cert_signed_path} -storepass #{password} -noprompt")
      end

      def create_server_properties
        say(__method__.to_s.tr("_", " ").titleize)

        content = <<~SERVER_PROPERTIES

          listeners=SASL_SSL://:9093

          ssl.keystore.location=#{keystore_path}
          ssl.keystore.password=#{password}
          ssl.key.password=#{password}

          ssl.truststore.location=#{truststore_path}
          ssl.truststore.password=#{password}

          ssl.client.auth=required

          sasl.enabled.mechanisms=PLAIN
          sasl.mechanism.inter.broker.protocol=PLAIN

          security.inter.broker.protocol=SASL_SSL
        SERVER_PROPERTIES

        return if file_contains?(server_properties_path, content)

        FileUtils.cp(server_properties_sample_path, server_properties_path)
        File.write(server_properties_path, content, :mode => "a")
      end

      def installation_valid?
        return true if LinuxAdmin::Rpm.list_installed.key?("kafka")

        say("\nAppliance Installation is not valid for enabling Message\n")
        false
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

      def deactivate
        remove_installed_files
        unconfigure_firewall
        deactivate_services
      end

      def unconfigure_firewall
        say(__method__.to_s.tr("_", " ").titleize)

        AwesomeSpawn.run!("firewall-cmd --remove-port=9092/tcp --permanent") # insecure
        AwesomeSpawn.run!("firewall-cmd --remove-port=9093/tcp --permanent") # secure
        AwesomeSpawn.run!("firewall-cmd --reload")
      end

      def deactivate_services
        say(__method__.to_s.tr("_", " ").titleize)

        LinuxAdmin::Service.new("zookeeper").stop
        LinuxAdmin::Service.new("kafka").stop
      end
    end
  end
end