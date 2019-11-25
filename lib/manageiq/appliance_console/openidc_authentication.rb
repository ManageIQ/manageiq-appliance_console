require "erb"

module ManageIQ
  module ApplianceConsole
    class OpenIDCAuthentication
      HTTPD_CONFIG_DIRECTORY = Pathname.new("/etc/httpd/conf.d")

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

      def restart_httpd
        httpd_service = LinuxAdmin::Service.new("httpd")
        if httpd_service.running?
          say("Restarting httpd ...")
          httpd_service.restart
        end
      end

      # OpenID-Connect IDP Metadata

      def validate_openidc_options
        raise "Must specify the OpenID-Connect Provider URL via --openidc-url" if options[:openidc_url].blank?
        raise "Must specify the OpenID-Connect Client ID via --openidc-client-id" if options[:openidc_client_id].blank?
        raise "Must specify the OpenID-Connect Client Secret via --openidc-client-secret" if options[:openidc_client_secret].blank?
      end

      def path_is_file?(path)
        path.present? && !path_is_url?(path)
      end

      def path_is_url?(path)
        path =~ /\A#{URI.regexp(["http", "https"])}\z/x
      end

      # File Management

      def remove_file(path)
        if path.exist?
          debug_msg("Removing #{path} ...")
          File.delete(path)
        end
      end

      def copy_template(dir, file, template_parameters = nil)
        src_path = template_directory.join(relative_from_root(dir), file)
        dest_path = dir.join(file)
        dest_path = dest_path.sub_ext('') if src_path.extname == ".erb"
        debug_msg("Copying template #{src_path} to #{dest_path} ...")
        if src_path.extname == ".erb"
          template = ERB.new(File.read(src_path), nil, '-')
          if template_parameters
            File.write(dest_path, template.result_with_hash(template_parameters))
          else
            File.write(dest_path, template.result(binding))
          end
        else
          FileUtils.cp(src_path, dest_path)
        end
      end

      def template_directory
        @template_directory ||= Pathname.new(ENV.fetch("APPLIANCE_TEMPLATE_DIRECTORY"))
      end

      def relative_from_root(path)
        path.absolute? ? path.relative_path_from(Pathname.new("/")) : path
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
        Utilities.rake_run("evm:settings:set", params)
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
