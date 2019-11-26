module ManageIQ
  module ApplianceConsole
    class OpenIDCAuthentication
      include ManageIQ::ApplianceConsole::AuthUtilities

      attr_accessor :host, :options

      def initialize(options)
        @options = options
      end

      def configure(host)
        @host = host
        validate_openidc_options

        say("Configuring OpenID-Connect Authentication for https://#{host} ...")
        copy_apache_openidc_configfiles
        configure_auth_settings_openidc
        restart_httpd
        true
      rescue AwesomeSpawn::CommandResultError => e
        log_command_error(e)
        say("Failed to Configure OpenID-Connect Authentication - #{e}")
        false
      rescue => e
        say("Failed to Configure OpenID-Connect Authentication - #{e}")
        false
      end

      def unconfigure
        raise "Appliance is not currently configured for OpenID-Connect" unless configured?

        say("Unconfiguring OpenID-Connect Authentication ...")
        remove_apache_openidc_configfiles
        configure_auth_settings_database
        restart_httpd
        true
      rescue AwesomeSpawn::CommandResultError => e
        log_command_error(e)
        say("Failed to Unconfigure OpenID-Connect Authentication - #{e}")
        false
      rescue => e
        say("Failed to Unconfigure OpenID-Connect Authentication - #{e}")
        false
      end

      private

      # Apache OpenID-Connect Configuration

      def copy_apache_openidc_configfiles
        debug_msg("Copying Apache OpenID-Connect Config files ...")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-openidc.conf.erb",
                      :miq_appliance              => host,
                      :oidc_provider_metadata_url => options[:openidc_url],
                      :oidc_client_id             => options[:openidc_client_id],
                      :oidc_client_secret         => options[:openidc_client_secret])
      end

      def remove_apache_openidc_configfiles
        debug_msg("Removing Apache OpenID-Connect Config files ...")
        remove_file(HTTPD_CONFIG_DIRECTORY.join("manageiq-remote-user-openidc.conf"))
        remove_file(HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-openidc.conf"))
      end

      def configured?
        HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-openidc.conf").exist?
      end

      # OpenID-Connect IDP Metadata

      def validate_openidc_options
        raise "Must specify the OpenID-Connect Provider URL via --openidc-url" if options[:openidc_url].blank?
        raise "Must specify the OpenID-Connect Client ID via --openidc-client-id" if options[:openidc_client_id].blank?
        raise "Must specify the OpenID-Connect Client Secret via --openidc-client-secret" if options[:openidc_client_secret].blank?
      end

      # Appliance Settings

      def configure_auth_settings_openidc
        say("Setting Appliance Authentication Settings to OpenID-Connect ...")
        params = [
          "/authentication/mode=httpd",
          "/authentication/httpd_role=true",
          "/authentication/saml_enabled=false",
          "/authentication/oidc_enabled=true",
          "/authentication/sso_enabled=#{options[:openidc_enable_sso] ? 'true' : 'false'}",
          "/authentication/provider_type=oidc"
        ]
        Utilities.rake_run("evm:settings:set", params)
      end
    end
  end
end
