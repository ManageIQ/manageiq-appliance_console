require_relative 'manageiq_user_mixin'

module ManageIQ
  module ApplianceConsole
    class ContainersConfiguration
      include ManageIQ::ApplianceConsole::Prompts
      include ManageIQ::ApplianceConsole::ManageiqUserMixin

      CONTAINERS_ROOT_DIR = Pathname.new("/var/lib/manageiq/containers").freeze
      CONTAINERS_VOL_NAME = "miq_containers".freeze

      attr_accessor :registry_uri, :registry_username, :registry_password,
                    :registry_authfile, :registry_certdir, :registry_tls_verify, :disk

      def initialize(options = {})
        self.registry_uri      = options[:container_registry_uri]
        self.registry_username = options[:container_registry_username]
        self.registry_password = options[:container_registry_password]
        self.registry_authfile = options[:container_registry_authfile]
        self.disk              = options[:disk]
      end

      def ask_questions
        clear_screen
        choose_disk if use_new_disk?
        choose_container_registry if authenticate_container_registry?
        confirm_selection
      end

      def activate
        if disk
          say("Initializing container storage disk")

          FileUtils.mkdir_p(CONTAINERS_ROOT_DIR)
          LogicalVolumeManagement.new(:disk => disk, :mount_point => CONTAINERS_ROOT_DIR, :name => CONTAINERS_VOL_NAME).setup
          FileUtils.chown(manageiq_uid, manageiq_gid, CONTAINERS_ROOT_DIR)
        end

        if registry_uri
          say("Authenticating to container registry #{registry_uri}...")

          login_params = {
            :username   => registry_username,
            :password   => registry_password,
            :authfile   => registry_authfile,
            :cert_dir   => registry_certdir,
            :tls_verify => registry_tls_verify
          }

          podman!("login", registry_uri, login_params.compact)
        end

        true
      end

      private

      def use_new_disk?
        agree("Configure a new disk for container storage? (Y/N):")
      end

      def choose_disk
        self.disk = ask_for_disk("container disk")
      end

      def authenticate_container_registry?
        agree("Authenticate to a container registry? (Y/N):")
      end

      def choose_container_registry
        self.registry_uri      = ask_for_string("Registry:")
        self.registry_username = ask_for_string("Registry username:")
        self.registry_password = ask_for_password("Registry password:")
      end

      def confirm_selection
        return false unless disk || registry_uri

        clear_screen

        if disk
          say("\t#{disk.path} with #{disk.size.to_i / 1.gigabyte} GB will be configured as the new containers root disk.")
        end

        if registry_uri
          say("Authenticating to container registry #{registry_uri}")
        end

        agree("Confirm continue with these updates (Y/N):")
      end

      def podman!(*args, **kwargs)
        params = [{:u => "manageiq"}, "podman", {:root => CONTAINERS_ROOT_DIR.join("storage")}]
        params.concat(args)

        AwesomeSpawn.run!("sudo", :params => params, **kwargs)
      end
    end
  end
end
