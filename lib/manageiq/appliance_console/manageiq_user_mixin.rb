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
    end
  end
end
