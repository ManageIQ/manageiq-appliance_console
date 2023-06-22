require 'awesome_spawn'

module ManageIQ
module ApplianceConsole
  # Kerberos principal
  class Principal
    attr_accessor :ca_name
    attr_accessor :hostname
    attr_accessor :realm
    attr_accessor :service
    # kerberos principal name
    attr_accessor :name
    attr_accessor :service_principal

    def initialize(options = {})
      options.each { |n, v| public_send("#{n}=", v) }
      @ca_name ||= "ipa"
      @realm = @realm.upcase if @realm
      @service_principal ||= "#{service}/#{hostname}"
      @name ||= "#{service_principal}@#{realm}"
    end

    def register
      request if ipa? && !exist?
    end

    def subject_name
      "CN=#{hostname},OU=#{service},O=#{realm}"
    end

    def ipa?
      @ca_name == "ipa"
    end

    private

    def exist?
      AwesomeSpawn.run("/usr/bin/ipa", :params => ["-e", "skip_version_check=1", "service-find", "--principal", service_principal]).success?
    end

    def request
      # using --force because these services tend not to be in dns
      # this is like VERIFY_NONE
      AwesomeSpawn.run!("/usr/bin/ipa", :params => ["-e", "skip_version_check=1", "service-add", "--force", service_principal])
    end
  end
end
end
