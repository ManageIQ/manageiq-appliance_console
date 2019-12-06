module ManageIQ
  module ApplianceConsole
    class OIDCAuthentication
      include ManageIQ::ApplianceConsole::AuthUtilities

      attr_accessor :host, :options

      def initialize(options)
        @options = options
      end

      def configure(host)
        @host = host
        validate_oidc_options

        say("Configuring OpenID-Connect Authentication for https://#{host} ...")
        copy_apache_oidc_configfiles
        configure_auth_settings_oidc
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
        remove_apache_oidc_configfiles
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

      def copy_apache_oidc_configfiles
        debug_msg("Copying Apache OpenID-Connect Config files ...")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf")
        copy_template(HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-openidc.conf.erb",
                      :miq_appliance              => host,
                      :oidc_provider_metadata_url => options[:oidc_url],
                      :oidc_client_id             => options[:oidc_client_id],
                      :oidc_client_secret         => options[:oidc_client_secret])
      end

      def remove_apache_oidc_configfiles
        debug_msg("Removing Apache OpenID-Connect Config files ...")
        remove_file(HTTPD_CONFIG_DIRECTORY.join("manageiq-remote-user-openidc.conf"))
        remove_file(HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-openidc.conf"))
      end

      def configured?
        HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-openidc.conf").exist?
      end

      # OpenID-Connect IDP Metadata

      def validate_oidc_options
        raise "Must specify the OpenID-Connect Provider URL via --oidc-url" if options[:oidc_url].blank?
        raise "Must specify the OpenID-Connect Client ID via --oidc-client-id" if options[:oidc_client_id].blank?
        raise "Must specify the OpenID-Connect Client Secret via --oidc-client-secret" if options[:oidc_client_secret].blank?
      end

      # Appliance Settings

      def configure_auth_settings_oidc
        say("Setting Appliance Authentication Settings to OpenID-Connect ...")
        configure_auth_settings(:mode          => "httpd",
                                :httpd_role    => true,
                                :saml_enabled  => false,
                                :oidc_enabled  => true,
                                :sso_enabled   => options[:oidc_enable_sso] ? true : false,
                                :provider_type => "oidc")
      end
    end
  end
end
