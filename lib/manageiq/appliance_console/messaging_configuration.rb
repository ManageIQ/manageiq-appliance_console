require "pathname"

module ManageIQ
  module ApplianceConsole
    class MessagingConfiguration
      include ManageIQ::ApplianceConsole::Logging
      include ManageIQ::ApplianceConsole::Prompts

      MESSAGING_YML = ManageIQ::ApplianceConsole::RAILS_ROOT.join("config/messaging.yml")

      attr_accessor :host, :password, :port, :username

      def run_interactive
        ask_questions

        clear_screen
        say("Activating the configuration using the following settings...\n#{friendly_inspect}\n")

        raise MiqSignalError unless activate

        say("\nConfiguration activated successfully.\n")
      rescue RuntimeError => e
        puts "Configuration failed#{": " + e.message unless e.class == MiqSignalError}"
        press_any_key
        raise MiqSignalError
      end

      def ask_questions
        ask_for_messaging_credentials
      end

      def ask_for_messaging_credentials
        self.host     = ask_for_ip_or_hostname("messaging hostname or IP address")
        self.port     = ask_for_integer("port number", (1..65_535), 9_092).to_i
        self.username = just_ask("username")
        count = 0
        loop do
          password1 = ask_for_password("messaging password on #{host}")

          if password1.strip.empty?
            say("\nPassword can not be empty, please try again")
            next
          end

          password2 = ask_for_password("messaging password again")
          if password1 == password2
            self.password = password1
            break
          elsif count > 0 # only reprompt password once
            raise "passwords did not match"
          else
            count += 1
            say("\nThe passwords did not match, please try again")
          end
        end
      end

      def friendly_inspect
        <<~END_OF_INSPECT
          Host:     #{host}
          Username: #{username}
          Port:     #{port}
        END_OF_INSPECT
      end

      def activate
        save
        true
      end

      private

      def settings_from_input
        {
          "hostname" => host,
          "password" => password,
          "port"     => port,
          "username" => username
        }
      end

      def save(settings = nil)
        settings ||= settings_from_input

        require 'yaml'
        File.write(MESSAGING_YML, YAML.dump("production" => settings))
      end
    end
  end
end
