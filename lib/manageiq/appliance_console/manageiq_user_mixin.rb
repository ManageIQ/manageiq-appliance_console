module ManageIQ
  module ApplianceConsole
    module ManageiqUserMixin
      extend ActiveSupport::Concern

      def manageiq_uid
        @manageiq_uid ||= Process::UID.from_name("manageiq")
      end

      def manageiq_gid
        @manageiq_gid ||= Process::GID.from_name("manageiq")
      end

      def run_as_manageiq!(options = {})
        options[:params].unshift({:user => "manageiq"})
        AwesomeSpawn.run!("sudo", options)
      end
    end
  end
end
