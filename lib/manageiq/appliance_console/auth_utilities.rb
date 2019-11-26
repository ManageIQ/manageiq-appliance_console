require "uri"
require "erb"

module ManageIQ
  module ApplianceConsole
    module AuthUtilities
      HTTPD_CONFIG_DIRECTORY = Pathname.new("/etc/httpd/conf.d")

      def restart_httpd
        httpd_service = LinuxAdmin::Service.new("httpd")
        if httpd_service.running?
          say("Restarting httpd ...")
          httpd_service.restart
        end
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
