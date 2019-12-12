module ManageIQ
  module ApplianceConsole
    class SamlAuthentication
      include ManageIQ::ApplianceConsole::AuthUtilities

      MELLON_CREATE_METADATA_COMMAND = Pathname.new("/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh")

      SAML2_CONFIG_DIRECTORY = Pathname.new("/etc/httpd/saml2")
      IDP_METADATA_FILE      = SAML2_CONFIG_DIRECTORY.join("idp-metadata.xml")

      attr_accessor :host, :options

      def initialize(options)
        @options = options
      end

      def configure(host)
        @host = host
        validate_saml_idp_metadata_option

        say("Configuring SAML Authentication for https://#{host} ...")
        copy_apache_saml_configfiles
        FileUtils.mkdir_p(SAML2_CONFIG_DIRECTORY)
        AwesomeSpawn.run!(MELLON_CREATE_METADATA_COMMAND,
                          :chdir  => SAML2_CONFIG_DIRECTORY,
                          :params => ["https://#{host}", "https://#{host}/saml2"])
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
            saml2_file =
              case mellon_file
              when /^https_.*\.key$/  then "miqsp-key.key"
              when /^https_.*\.cert$/ then "miqsp-cert.cert"
              when /^https_.*\.xml$/  then "miqsp-metadata.xml"
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
        if path_is_file?(idp_metadata) && idp_metadata != IDP_METADATA_FILE
          debug_msg("Copying IDP metadata file #{idp_metadata} to #{IDP_METADATA_FILE} ...")
          FileUtils.cp(idp_metadata, IDP_METADATA_FILE)
        elsif path_is_url?(idp_metadata)
          debug_msg("Downloading IDP metadata file from #{idp_metadata}")
          download_network_file(idp_metadata, IDP_METADATA_FILE)
        end
      end

      def copy_apache_saml_configfiles
        debug_msg("Copying Apache SAML Config files ...")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user.conf")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf")
      end

      def remove_apache_saml_configfiles
        debug_msg("Removing Apache SAML Config files ...")
        remove_file(HTTPD_CONFIG_DIRECTORY.join("manageiq-remote-user.conf"))
        remove_file(HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-saml.conf"))
      end

      def configured?
        HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-saml.conf").exist?
      end

      # SAML IDP Metadata

      def validate_saml_idp_metadata_option
        idp_metadata = options[:saml_idp_metadata]
        raise "Must specify the SAML IDP metadata file or URL via --saml-idp-metadata" if idp_metadata.blank?

        raise "Missing SAML IDP metadata file #{idp_metadata}" if path_is_file?(idp_metadata) && !File.exist?(idp_metadata)
      end

      # File Management

      def download_network_file(source_file_url, target_file)
        require "net/http"

        say("Downloading #{source_file_url} ...")
        result = Net::HTTP.get_response(URI(source_file_url))
        raise "Failed to download file from #{source_file_url}" unless result.kind_of?(Net::HTTPSuccess)

        File.write(target_file, result.body)
      end

      # Appliance Settings

      def configure_auth_settings_saml
        say("Setting Appliance Authentication Settings to SAML ...")
        configure_auth_settings(:mode          => "httpd",
                                :httpd_role    => true,
                                :saml_enabled  => true,
                                :oidc_enabled  => false,
                                :sso_enabled   => options[:saml_enable_sso] ? true : false,
                                :provider_type => "saml")
      end
    end
  end
end
