require_relative 'manageiq_user_mixin'

module ManageIQ
  module ApplianceConsole
    class ContainersConfiguration
      include ManageIQ::ApplianceConsole::Prompts
      include ManageIQ::ApplianceConsole::ManageiqUserMixin

      CONTAINERS_ROOT_DIR = Pathname.new("/var/lib/manageiq/containers").freeze
      CONTAINERS_VOL_NAME = "miq_containers".freeze

      attr_accessor :registry_uri, :registry_username, :registry_password,
                    :registry_authfile, :registry_certdir, :registry_tls_verify,
                    :disk, :image

      def initialize(options = {})
        self.registry_uri        = options[:container_registry_uri]
        self.registry_username   = options[:container_registry_username]
        self.registry_password   = options[:container_registry_password]
        self.registry_authfile   = options[:container_registry_authfile]
        self.registry_tls_verify = options[:conatiner_registry_tls_verify]
        self.image               = options[:container_image]
        self.disk                = options[:disk]
      end

      def ask_questions
        clear_screen
        choose_disk               if use_new_disk?
        choose_container_registry if authenticate_container_registry?
        choose_container_image    if pull_container_image?
        confirm_selection
      end

      def activate
        activate_new_disk       if disk
        activate_registry_login if registry_uri
        activate_image_pull     if image
        true
      rescue AwesomeSpawn::CommandResultError => e
        say(e.result.output)
        say(e.result.error)
        say("")
        false
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
        self.registry_uri      = ask_for_string("Registry")
        self.registry_username = ask_for_string("Registry username")
        self.registry_password = ask_for_password("Registry password")
      end

      def pull_container_image?
        agree("Pull a container image? (Y/N):")
      end

      def choose_container_image
        self.image = ask_for_string("Container image")
      end

      def confirm_selection
        return false unless disk || registry_uri || image

        clear_screen

        if disk
          say("\t#{disk.path} with #{disk.size.to_i / 1.gigabyte} GB will be configured as the new containers root disk.")
        end

        if registry_uri
          say("Authenticating to container registry #{registry_uri}")
        end

        if image
          say("Pull container image #{image}")
        end

        agree("Confirm continue with these updates (Y/N):")
      end

      def activate_new_disk
        say("Initializing container storage disk")

        FileUtils.mkdir_p(CONTAINERS_ROOT_DIR)
        LogicalVolumeManagement.new(:disk => disk, :mount_point => CONTAINERS_ROOT_DIR, :name => CONTAINERS_VOL_NAME).setup
        FileUtils.chown(manageiq_uid, manageiq_gid, CONTAINERS_ROOT_DIR)
      end

      def activate_registry_login
        say("Authenticating to container registry #{registry_uri}...")

        extra_opts   = {}
        login_params = {}
        login_params[:username]       = registry_username if registry_username
        login_params[:authfile]       = registry_authfile if registry_authfile
        login_params[:cert_dir]       = registry_certdir  if registry_certdir.present?
        login_params[:tls_verify]     = nil               if registry_tls_verify

        if registry_password
          login_params[:password_stdin] = nil
          extra_opts[:in_data] = "#{registry_password}\n"
        end

        podman!(:params => ["login", registry_uri, login_params], **extra_opts)
      end

      def activate_image_pull
        say("Pulling container image #{image}...")

        podman!("image", "pull", image)
      end

      def podman!(options = {})
        options[:params].unshift("podman", {:root => CONTAINERS_ROOT_DIR.join("storage").to_s})
        run_as_manageiq!(options)
      end
    end
  end
end
