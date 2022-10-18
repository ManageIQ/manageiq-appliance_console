module ManageIQ
  module ApplianceConsole
    class EvmServer
      class NotRunnableError < RuntimeError; end

      class << self
        def running?
          service.running?
        end

        def start!(enable: false)
          raise NotRunnableError, "Cannot start #{I18n.t("product.name")}: #{not_runnable_reason}" unless runnable?

          service.start(enable)
        end

        def start(enable: false)
          start!(:enable => enable)
        rescue AwesomeSpawn::CommandResultError => e
          say(e.result.output)
          say(e.result.error)
          say("")
          false
        rescue NotRunnableError => e
          say(e.to_s)
          say("")
          false
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

        def runnable?
          DatabaseConfiguration.database_yml_configured? && MessageConfiguration.configured?
        end

        def not_runnable_reason
          if !DatabaseConfiguration.database_yml_configured?
            "A Database connection has not been configured."
          elsif !MessageConfiguration.configured?
            "Messaging has not been configured."
          end
        end

        private

        def service
          @service ||= LinuxAdmin::Service.new("evmserverd")
        end
      end
    end
  end
end
