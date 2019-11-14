require "uri"

module ManageIQ
  module ApplianceConsole
    class SamlAuthentication
      MELLON_CREATE_METADATA_COMMAND = "/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh".freeze

      HTTPD_CONFIG_DIRECTORY = "/etc/httpd/conf.d".freeze
      SAML2_CONFIG_DIRECTORY = "/etc/httpd/saml2".freeze
      IDP_METADATA_FILE      = "#{SAML2_CONFIG_DIRECTORY}/idp-metadata.xml".freeze

      attr_accessor :host, :options

      def initialize(options)
        @options = options
      end

      def configure(host)
        @host = host
        validate_saml_idp_metadata_option

        say("Configuring SAML Authentication for https://#{host} ...")
        copy_apache_saml_configfiles
        Dir.mkdir(SAML2_CONFIG_DIRECTORY) unless File.exist?(SAML2_CONFIG_DIRECTORY)
        Dir.chdir(SAML2_CONFIG_DIRECTORY) do
          AwesomeSpawn.run!(MELLON_CREATE_METADATA_COMMAND,
                            :params => ["https://#{host}", "https://#{host}/saml2"])
        end
        rename_mellon_configfiles
        fetch_idp_metadata
        configure_auth_settings_saml
        restart_httpd
        true
      rescue AwesomeSpawn::CommandResultError => e
        log_command_error(e)
        say("Failed to Configure SAML Authentication - #{e}")
        false
      rescue => e
        say("Failed to Configure SAML Authentication - #{e}")
        false
      end

      def unconfigure
        raise "Appliance is not currently configured for SAML" unless configured?

        say("Unconfiguring SAML Authentication ...")
        remove_mellon_configfiles
        remove_apache_saml_configfiles
        configure_auth_settings_database
        restart_httpd
        true
      rescue AwesomeSpawn::CommandResultError => e
        log_command_error(e)
        say("Failed to Unconfigure SAML Authentication - #{e}")
        false
      rescue => e
        say("Failed to Unconfigure SAML Authentication - #{e}")
        false
      end

      private

      # Apache SAML Configuration

      def rename_mellon_configfiles
        debug_msg("Renaming mellon config files ...")
        Dir.chdir(SAML2_CONFIG_DIRECTORY) do
          Dir.glob("https_*.*") do |mellon_file|
            saml2_file = nil
            case mellon_file
            when /^https_.*\.key$/  then saml2_file = "miqsp-key.key"
            when /^https_.*\.cert$/ then saml2_file = "miqsp-cert.cert"
            when /^https_.*\.xml$/  then saml2_file = "miqsp-metadata.xml"
            end
            if saml2_file
              debug_msg("Renaming #{mellon_file} to #{saml2_file}")
              File.rename(mellon_file, saml2_file)
            end
          end
        end
      end

      def fetch_idp_metadata
        idp_metadata = options[:saml_idp_metadata]
        if path_is_file(idp_metadata) && idp_metadata != IDP_METADATA_FILE
          debug_msg("Copying IDP metadata file #{idp_metadata} to #{IDP_METADATA_FILE} ...")
          FileUtils.cp(idp_metadata, IDP_METADATA_FILE)
        elsif path_is_url(idp_metadata)
          debug_msg("Downloading IDP metadata file from #{idp_metadata}")
          download_network_file(idp_metadata, IDP_METADATA_FILE)
        end
      end

      def remove_mellon_configfiles
        debug_msg("Removing mellon config files ...")
        remove_file(SAML2_CONFIG_DIRECTORY, "miqsp-key.key")
        remove_file(SAML2_CONFIG_DIRECTORY, "miqsp-cert.cert")
        remove_file(SAML2_CONFIG_DIRECTORY, "miqsp-metadata.xml")
        remove_file(IDP_METADATA_FILE)
      end

      def copy_apache_saml_configfiles
        debug_msg("Copying Apache SAML Config files ...")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user.conf")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf")
      end

      def remove_apache_saml_configfiles
        debug_msg("Removing Apache SAML Config files ...")
        remove_file(HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user.conf")
        remove_file(HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf")
      end

      def configured?
        path_join(HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf").exist?
      end

      def restart_httpd
        say("Restarting httpd ...")
        LinuxAdmin::Service.new("httpd").restart
      end

      # SAML IDP Metadata

      def validate_saml_idp_metadata_option
        idp_metadata = options[:saml_idp_metadata]
        raise "Must specify the SAML IDP metadata file or URL via --saml-idp-metadata" if idp_metadata.blank?

        raise "Missing SAML IDP metadata file #{idp_metadata}" if path_is_file(idp_metadata) && !File.exist?(idp_metadata)
      end

      def path_is_file(path)
        path.present? && !path_is_url(path)
      end

      def path_is_url(path)
        path =~ /\A#{URI.regexp(["http", "https"])}\z/
      end

      # File Management

      def remove_file(*args)
        path = path_join(*args)
        if path.exist?
          debug_msg("Removing #{path} ...")
          File.delete(path)
        end
      end

      def copy_template(dir, file)
        src_path = path_join(template_directory, dir, file)
        dest_path = path_join(dir, file)
        debug_msg("Copying template #{src_path} to #{dest_path} ...")
        FileUtils.cp(src_path, dest_path)
      end

      def download_network_file(source_file_url, target_file)
        require "net/http"

        say("Downloading #{source_file_url} ...")
        result = Net::HTTP.get_response(URI(source_file_url))
        raise "Failed to download file from #{source_file_url}" unless result.kind_of?(Net::HTTPSuccess)

        File.write(target_file, result.body)
      end

      def template_directory
        @template_directory ||= Pathname.new(ENV.fetch("APPLIANCE_TEMPLATE_DIRECTORY"))
      end

      def path_join(*args)
        path = Pathname.new(args.shift)
        args.each { |path_seg| path = path.join("./#{path_seg}") }
        path
      end

      # Appliance Settings

      def configure_auth_settings_saml
        say("Setting Appliance Authentication Settings to SAML ...")
        params = [
          "/authentication/mode=httpd",
          "/authentication/httpd_role=true",
          "/authentication/saml_enabled=true",
          "/authentication/oidc_enabled=false",
          "/authentication/sso_enabled=#{options[:saml_enable_sso] ? 'true' : 'false'}",
          "/authentication/provider_type=saml"
        ]
        ManageIQ::ApplianceConsole::Utilities.rake_run("evm:settings:set", params)
      end

      def configure_auth_settings_database
        say("Setting Appliance Authentication Settings to Database ...")
        params = [
          "/authentication/mode=database",
          "/authentication/httpd_role=false",
          "/authentication/saml_enabled=false",
          "/authentication/oidc_enabled=false",
          "/authentication/sso_enabled=false",
          "/authentication/provider_type=none"
        ]
        ManageIQ::ApplianceConsole::Utilities.rake_run("evm:settings:set", params)
      end

      # Logging

      def debug_msg(msg)
        say(msg) if options[:verbose]
      end

      def log_command_error(err)
        say(err.result.output)
        say(err.result.error)
        say("")
      end
    end
  end
end
