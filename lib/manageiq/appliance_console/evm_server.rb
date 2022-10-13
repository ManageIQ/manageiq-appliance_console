module ManageIQ
  module ApplianceConsole
    class EvmServer
      class << self
        def running?
          service.running?
        end

        def start!(enable: false)
          service.start(enable)
        end

        def start(enable: false)
          start!(:enable => enable)
        rescue AwesomeSpawn::CommandResultError => e
          say e.result.output
          say e.result.error
          say ""
        end

        def stop
          service.stop
        end

        def restart
          service.restart
        end

        def enable
          service.enable
        end

        def disable
          service.disable
        end

        private

        def service
          @service ||= LinuxAdmin::Service.new("evmserverd")
        end
      end
    end
  end
end
