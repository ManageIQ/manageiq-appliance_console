require "awesome_spawn"
require "fileutils"
require "linux_admin"
require 'net/scp'
require "manageiq/appliance_console/message_configuration"

module ManageIQ
  module ApplianceConsole
    class MessageClientConfiguration < MessageConfiguration
      attr_reader :message_server_password, :message_server_username, :installed_files

      def initialize(options = {})
        super(options)

        @message_server_host         = options[:message_server_host]
        @message_server_username     = options[:message_server_usernamed] || "root"
        @message_server_password     = options[:message_server_password]

        @message_truststore_path_src = options[:message_truststore_path_src] || truststore_path
        @message_ca_cert_path_src    = options[:message_ca_cert_path_src] || ca_cert_path

        @installed_files = [client_properties_path, messaging_yaml_path, truststore_path]
      end

      def configure
        begin
          configure_messaging_yaml          # Set up the local message client in case EVM is actually running on this, Message Server
          create_client_properties          # Create the client.properties configuration fle
          fetch_truststore_from_server      # Fetch the Java Keystore from the Kafka Server
          configure_messaging_type("kafka") # Settings.prototype.messaging_type = 'kafka'
          restart_evmserverd
        rescue AwesomeSpawn::CommandResultError => e
          say(e.result.output)
          say(e.result.error)
          say("")
          say("Failed to Configure the Message Client- #{e}")
          return false
        rescue => e
          say("Failed to Configure the Message Client- #{e}")
          return false
        end
        true
      end

      def ask_for_parameters
        say("\nMessage Client Parameters:\n\n")

        @message_server_host         = ask_for_string("Message Server Hostname or IP address")
        @message_server_port         = ask_for_integer("Message Server Port number", (1..65_535), 9_093).to_i
        @message_server_username     = ask_for_string("Message Server Username", message_server_username)
        @message_server_password     = ask_for_password("Message Server Password")
        @message_truststore_path_src = ask_for_string("Message Server Truststore Path", truststore_path)
        @message_ca_cert_path_src    = ask_for_string("Message Server CA Cert Path", ca_cert_path)
        @message_keystore_username   = ask_for_string("Message Keystore Username", message_keystore_username) if secure?
        @message_keystore_password   = ask_for_password("Message Keystore Password") if secure?
      end

      def show_parameters
        say("\nMessage Client Configuration:\n")
        say("Message Client Details:\n")
        say("  Message Server Hostname:   #{message_server_host}\n")
        say("  Message Server Username:   #{message_server_username}\n")
        say("  Message Keystore Username: #{message_keystore_username}\n")
      end

      def fetch_truststore_from_server
        say(__method__.to_s.tr("_", " ").titleize)

        fetch_from_server(message_truststore_path_src, truststore_path)
      end

      def fetch_ca_cert_from_server
        say(__method__.to_s.tr("_", " ").titleize)

        fetch_from_server(message_ca_cert_path_src, ca_cert_path)
      end

      private

      def fetch_from_server(src_file, dst_file)
        return if file_found?(dst_file)

        Net::SCP.start(message_server_host, message_server_username, :password => message_server_password) do |scp|
          scp.download!(src_file, dst_file)
        end

        File.exist?(dst_file)
      rescue => e
        say("Failed to fetch #{src_file} from server: #{e.message}")
        false
      end
    end
  end
end
