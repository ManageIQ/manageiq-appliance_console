require "awesome_spawn"
require "fileutils"
require "linux_admin"
require "manageiq/appliance_console/message_configuration"

module ManageIQ
  module ApplianceConsole
    class MessageServerConfiguration < MessageConfiguration
      attr_reader :jaas_config_path,
                  :server_properties_path, :server_properties_sample_path,
                  :ca_cert_srl_path, :ca_key_path, :cert_file_path, :cert_signed_path,
                  :keystore_files, :installed_files

      def initialize(options = {})
        super(options)

        @message_server_host = options[:message_server_host] || my_hostname

        @jaas_config_path              = config_dir_path.join("kafka_server_jaas.conf")
        @server_properties_path        = config_dir_path.join("server.properties")
        @server_properties_sample_path = sample_config_dir_path.join("server.properties")

        @ca_cert_srl_path              = keystore_dir_path.join("ca-cert.srl")
        @ca_key_path                   = keystore_dir_path.join("ca-key")
        @cert_file_path                = keystore_dir_path.join("cert-file")
        @cert_signed_path              = keystore_dir_path.join("cert-signed")

        @keystore_files  = [ca_cert_path, ca_cert_srl_path, ca_key_path, cert_file_path, cert_signed_path, truststore_path, keystore_path]
        @installed_files = [jaas_config_path, client_properties_path, server_properties_path, messaging_yaml_path, LOGS_DIR] + keystore_files
      end

      def activate
        begin
          create_jaas_config                # Create the message server jaas config file
          create_client_properties          # Create the client.properties config
          create_logs_directory             # Create the logs directory:
          configure_firewall                # Open the firewall for message port 9093
          configure_keystore                # Populate the Java Keystore
          create_server_properties          # Update the /opt/message/config/server.properties
          configure_messaging_yaml          # Set up the local message client in case EVM is actually running on this, Message Server
          configure_messaging_type("kafka") # Settings.prototype.messaging_type = 'kafka'
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

        restart_evmserverd
      end

      def ask_for_parameters
        say("\nMessage Server Parameters:\n\n")

        @message_server_host       = ask_for_string("Message Server Hostname or IP address", message_server_host)
        @message_keystore_username = ask_for_string("Message Keystore Username", message_keystore_username)
        @message_keystore_password = ask_for_password("Message Keystore Password")
      end

      def show_parameters
        say("\nMessage Server Configuration:\n")
        say("Message Server Details:\n")
        say("  Message Server Hostname:   #{message_server_host}\n")
        say("  Message Keystore Username: #{message_keystore_username}\n")
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
            username=#{message_keystore_username}
            password=#{message_keystore_password}
            user_admin=#{message_keystore_password} ;
          };
        JAAS

        File.write(jaas_config_path, content) unless file_found?(jaas_config_path)
      end

      def create_logs_directory
        say(__method__.to_s.tr("_", " ").titleize)

        return if file_found?(LOGS_DIR)

        FileUtils.mkdir_p(LOGS_DIR)
        FileUtils.chmod(0o755, LOGS_DIR)
        FileUtils.chown("kafka", "kafka", LOGS_DIR)
      end

      def configure_firewall
        say(__method__.to_s.tr("_", " ").titleize)

        modify_firewall(:add_port)
      end

      def configure_keystore
        say(__method__.to_s.tr("_", " ").titleize)

        return if files_found?(keystore_files)

        keystore_params = assemble_keystore_params

        # Generte a Java keystore and key pair, creating keystore.jks
        AwesomeSpawn.run!("keytool", :params => keystore_params)

        # Use openssl to create a new CA cert, creating ca-cert and ca-key
        AwesomeSpawn.run!("openssl", :env => {"PASSWORD" => message_keystore_password}, :params => ["req", "-new", "-x509", {"-keyout" => ca_key_path, "-out" => ca_cert_path, "-days" => 10_000, "-passout" => "env:PASSWORD", "-subj" => '/CN=something'}])

        # Import the CA cert into the trust store, creating truststore.jks
        AwesomeSpawn.run!("keytool", :params => {"-keystore" => truststore_path, "-alias" => "CARoot", "-import" => nil, "-file" => ca_cert_path, "-storepass" => message_keystore_password, "-noprompt" => nil})

        # Generate a certificate signing request (CSR) for an existing Java keystore, creating cert-file
        AwesomeSpawn.run!("keytool", :params => {"-keystore" => keystore_path, "-alias" => keystore_params["-alias"], "-certreq" => nil, "-file" => cert_file_path, "-storepass" => message_keystore_password})

        # Use openssl to sign the certificate with the "CA" certificate, creating ca-cert.srl and cert-signed
        AwesomeSpawn.run!("openssl", :env => {"PASSWORD" => message_keystore_password}, :params => ["x509", "-req", {"-CA" => ca_cert_path, "-CAkey" => ca_key_path, "-in" => cert_file_path, "-out" => cert_signed_path, "-days" => 10_000, "-CAcreateserial" => nil, "-passin" => "env:PASSWORD"}])

        # Import a root or intermediate CA certificate to an existing Java keystore, updating keystore.jks
        AwesomeSpawn.run!("keytool", :params => {"-keystore" => keystore_path, "-alias" => "CARoot", "-import" => nil, "-file" => ca_cert_path, "-storepass" => message_keystore_password, "-noprompt" => nil})

        # Import a signed primary certificate to an existing Java keystore, updating keystore.jks
        AwesomeSpawn.run!("keytool", :params => {"-keystore" => keystore_path, "-alias" => keystore_params["-alias"], "-import" => nil, "-file" => cert_signed_path, "-storepass" => message_keystore_password, "-noprompt" => nil})
      end

      def create_server_properties
        say(__method__.to_s.tr("_", " ").titleize)

        if message_server_host.ipaddress?
          ident_algorithm = ""
          client_auth = "none"
        else
          ident_algorithm = "HTTPS"
          client_auth = "required"
        end

        content = <<~SERVER_PROPERTIES

          listeners=SASL_SSL://:#{message_server_port}

          ssl.endpoint.identification.algorithm=#{ident_algorithm}
          ssl.keystore.location=#{keystore_path}
          ssl.keystore.password=#{message_keystore_password}
          ssl.key.password=#{message_keystore_password}

          ssl.truststore.location=#{truststore_path}
          ssl.truststore.password=#{message_keystore_password}

          ssl.client.auth=#{client_auth}

          sasl.enabled.mechanisms=PLAIN
          sasl.mechanism.inter.broker.protocol=PLAIN

          security.inter.broker.protocol=SASL_SSL
        SERVER_PROPERTIES

        return if file_contains?(server_properties_path, content)

        FileUtils.cp(server_properties_sample_path, server_properties_path)
        File.write(server_properties_path, content, :mode => "a")
      end

      def deactivate
        super

        unconfigure_firewall
        deactivate_services
      end

      def unconfigure_firewall
        say(__method__.to_s.tr("_", " ").titleize)

        modify_firewall(:remove_port)
      end

      def deactivate_services
        say(__method__.to_s.tr("_", " ").titleize)

        LinuxAdmin::Service.new("zookeeper").stop
        LinuxAdmin::Service.new("kafka").stop
      end

      def assemble_keystore_params
        keystore_params = {"-keystore"  => keystore_path,
                           "-validity"  => 10_000,
                           "-genkey"    => nil,
                           "-keyalg"    => "RSA",
                           "-storepass" => message_keystore_password,
                           "-keypass"   => message_keystore_password}

        if message_server_host.ipaddress?
          keystore_params["-alias"] = "localhost"
          keystore_params["-ext"] = "san=ip:#{message_server_host}"
        else
          keystore_params["-alias"] = message_server_host
          keystore_params["-ext"] = "san=dns:#{message_server_host}"
        end

        keystore_params["-dname"] = "cn=#{keystore_params["-alias"]}"

        keystore_params
      end

      def modify_firewall(action)
        AwesomeSpawn.run!("firewall-cmd", :params => {action => "#{message_server_port}/tcp", :permanent => nil})
        AwesomeSpawn.run!("firewall-cmd --reload")
      end
    end
  end
end
