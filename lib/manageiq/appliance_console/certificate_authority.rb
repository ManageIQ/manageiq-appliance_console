require 'fileutils'
require 'tempfile'
require 'manageiq/appliance_console/postgres_admin'

module ManageIQ
module ApplianceConsole
  class CertificateAuthority
    CFME_DIR        = "/var/www/miq/vmdb/certs"

    # hostname of current machine
    attr_accessor :hostname
    attr_accessor :realm
    # name of certificate authority
    attr_accessor :ca_name
    # true if we should configure http endpoint
    attr_accessor :http
    attr_accessor :verbose

    def initialize(options = {})
      options.each { |n, v| public_send("#{n}=", v) }
      @ca_name ||= "ipa"
    end

    def ask_questions
      if ipa?
        self.principal = just_ask("IPA Server Principal", @principal)
        self.password  = ask_for_password("IPA Server Principal Password", @password)
      end
      self.http = ask_yn("Configure certificate for http server", "Y")
      true
    end

    def activate
      valid_environment?

      configure_http if http

      status_string
    end

    def valid_environment?
      if ipa? && !ExternalHttpdAuthentication.ipa_client_configured?
        raise ArgumentError, "ipa client not configured"
      end

      raise ArgumentError, "hostname needs to be defined" unless hostname
    end

    def configure_http
      cert = Certificate.new(
        :key_filename  => "#{CFME_DIR}/server.cer.key",
        :cert_filename => "#{CFME_DIR}/server.cer",
        :root_filename => "#{CFME_DIR}/root.crt",
        :service       => "HTTP",
        :extensions    => %w(server),
        :ca_name       => ca_name,
        :hostname      => hostname,
        :owner         => "apache.apache",
      ).request
      if cert.complete?
        say "configuring apache to use new certs"
        LinuxAdmin::Service.new("httpd").restart

        cert.enable_certmonger
      end
      self.http = cert.status
    end

    def status
      {"http" => http}.delete_if { |_n, v| !v }
    end

    def status_string
      status.collect { |n, v| "#{n}: #{v}" }.join " "
    end

    def complete?
      !status.values.detect { |v| v != ManageIQ::ApplianceConsole::Certificate::STATUS_COMPLETE }
    end

    def ipa?
      ca_name == "ipa"
    end

    private

    def log
      say yield if verbose && block_given?
    end
  end
end
end
