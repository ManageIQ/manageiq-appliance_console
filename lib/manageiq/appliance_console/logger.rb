require 'logger'

module ManageIQ
  module ApplianceConsole
    class Logger < ::Logger
      def self.log_dir
        @log_dir ||= ManageIQ::ApplianceConsole::RAILS_ROOT.join("log")
      end

      def self.log_file
        @log_file ||= log_dir.join("appliance_console.log").to_s
      end

      def self.instance
        @instance ||= begin
          require 'fileutils'
          FileUtils.mkdir_p(log_dir.to_s)
          new(log_file).tap { |l| l.level = Logger::INFO }
        end
      end
    end
  end
end
