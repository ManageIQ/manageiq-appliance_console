require_relative 'manageiq_user_mixin'

module ManageIQ
  module ApplianceConsole
    class ContainersConfiguration
      include ManageIQ::ApplianceConsole::Prompts
      include ManageIQ::ApplianceConsole::ManageiqUserMixin

      CONTAINERS_ROOT_DIR = Pathname.new("/var/lib/manageiq/containers").freeze
      CONTAINERS_VOL_NAME = "miq_containers".freeze

      attr_accessor :disk

      def initialize(options = {})
        self.disk = options[:disk]
      end

      def ask_questions
        clear_screen
        choose_disk if use_new_disk
        confirm_selection
      end

      def activate
        return true unless disk

        say("Initializing container storage disk")

        FileUtils.mkdir_p(CONTAINERS_ROOT_DIR)
        LogicalVolumeManagement.new(:disk => disk, :mount_point => CONTAINERS_ROOT_DIR, :name => CONTAINERS_VOL_NAME).setup
        FileUtils.chown(manageiq_uid, manageiq_gid, CONTAINERS_ROOT_DIR)
        true
      end

      private

      def use_new_disk
        agree("Configure a new disk for container storage? (Y/N):")
      end

      def choose_disk
        self.disk = ask_for_disk("container disk")
      end

      def confirm_selection
        return false unless disk

        clear_screen

        say("\t#{disk.path} with #{disk.size.to_i / 1.gigabyte} GB will be configured as the new containers root disk.")

        agree("Confirm continue with these updates (Y/N):")
      end
    end
  end
end
