describe ManageIQ::ApplianceConsole::OIDCAuthentication do
  let(:client_host) { "client.example.com" }
  let(:oidc_url) { "http://oidc.example.com:8080/auth/realms/manageiq/.well-known/openid-configuration" }
  let(:oidc_introspection) { "http://oidc.example.com:8080/auth/realms/manageiq/protocol/openid-connect/token/introspect" }

  context "configuring OpenID-Connect" do
    it "fails without the oidc-url option specified" do
      subject = described_class.new({})

      expect(subject).to receive(:say).with(/Must specify the OpenID-Connect Provider URL via --oidc-url/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "fails without the oidc-client-id option specified" do
      subject = described_class.new(:oidc_url => oidc_url)

      expect(subject).to receive(:say).with(/Must specify the OpenID-Connect Client ID via --oidc-client-id/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "fails without the oidc-client-secret option specified" do
      subject = described_class.new(:oidc_url => "http://oidc.provider.example.com", :oidc_client_id => client_host)

      expect(subject).to receive(:say).with(/Must specify the OpenID-Connect Client Secret via --oidc-client-secret/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "fails when unable to derive introspect endpoint" do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(double(:body => {}.to_json))
      oidc_client_id     = client_host
      oidc_client_secret = "17106c0d-8446-4b87-82e4-b7408ad583d0"
      subject = described_class.new(:oidc_url           => "http://oidc.provider.example.com/.not-so-well-known",
                                    :oidc_client_id     => oidc_client_id,
                                    :oidc_client_secret => oidc_client_secret)

      expect(subject).to receive(:say).with(/Unable to derive the OpenID-Connect Client Introspection Endpoint/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "succeeds with provider url, client id and secret specified, fetches introspect from metadata and restarts httpd" do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(double(:body => {"introspection_endpoint" => oidc_introspection}.to_json))
      httpd_service = double(@spec_name, :running? => true)
      expect(httpd_service).to receive(:restart)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(httpd_service)

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with("evm:settings:set",
                                                                               ["/authentication/mode=httpd",
                                                                                "/authentication/httpd_role=true",
                                                                                "/authentication/saml_enabled=false",
                                                                                "/authentication/oidc_enabled=true",
                                                                                "/authentication/sso_enabled=false",
                                                                                "/authentication/provider_type=oidc"])

      oidc_client_id     = client_host
      oidc_client_secret = "17106c0d-8446-4b87-82e4-b7408ad583d0"
      subject = described_class.new(:oidc_url           => oidc_url,
                                    :oidc_client_id     => oidc_client_id,
                                    :oidc_client_secret => oidc_client_secret)

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY,
                                                      "manageiq-external-auth-openidc.conf.erb",
                                                      :miq_appliance               => client_host,
                                                      :oidc_client_id              => oidc_client_id,
                                                      :oidc_client_secret          => oidc_client_secret,
                                                      :oidc_introspection_endpoint => oidc_introspection,
                                                      :oidc_provider_metadata_url  => oidc_url).and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to OpenID-Connect ...")
      expect(subject).to receive(:say).with("Configuring OpenID-Connect Authentication for https://#{client_host} ...")

      expect(subject).to receive(:say).with("Restarting httpd ...")
      expect(subject.configure(client_host)).to eq(true)
    end

    it "succeeds with provider url, client id secret and introspect specified and restarts httpd" do
      httpd_service = double(@spec_name, :running? => true)
      expect(httpd_service).to receive(:restart)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(httpd_service)

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with("evm:settings:set",
                                                                               ["/authentication/mode=httpd",
                                                                                "/authentication/httpd_role=true",
                                                                                "/authentication/saml_enabled=false",
                                                                                "/authentication/oidc_enabled=true",
                                                                                "/authentication/sso_enabled=false",
                                                                                "/authentication/provider_type=oidc"])

      oidc_client_id     = client_host
      oidc_client_secret = "17106c0d-8446-4b87-82e4-b7408ad583d0"
      subject = described_class.new(:oidc_url                    => oidc_url,
                                    :oidc_client_id              => oidc_client_id,
                                    :oidc_client_secret          => oidc_client_secret,
                                    :oidc_introspection_endpoint => oidc_introspection)

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY,
                                                      "manageiq-external-auth-openidc.conf.erb",
                                                      :miq_appliance               => client_host,
                                                      :oidc_client_id              => oidc_client_id,
                                                      :oidc_client_secret          => oidc_client_secret,
                                                      :oidc_introspection_endpoint => oidc_introspection,
                                                      :oidc_provider_metadata_url  => oidc_url).and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to OpenID-Connect ...")
      expect(subject).to receive(:say).with("Configuring OpenID-Connect Authentication for https://#{client_host} ...")

      expect(subject).to receive(:say).with("Restarting httpd ...")
      expect(subject.configure(client_host)).to eq(true)
    end

    it "succeeds with client host, enabling SSO, and restarts httpd" do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(double(:body => {"introspection_endpoint" => oidc_introspection}.to_json))
      httpd_service = double(@spec_name, :running? => true)
      expect(httpd_service).to receive(:restart)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(httpd_service)

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with("evm:settings:set",
                                                                               ["/authentication/mode=httpd",
                                                                                "/authentication/httpd_role=true",
                                                                                "/authentication/saml_enabled=false",
                                                                                "/authentication/oidc_enabled=true",
                                                                                "/authentication/sso_enabled=true",
                                                                                "/authentication/provider_type=oidc"])

      alternate_client_host = "alternate.example.com"
      oidc_client_id        = alternate_client_host
      oidc_client_secret    = "18106c0d-8456-4b87-83e5-c74a9ad583e0"
      subject = described_class.new(:oidc_url           => oidc_url,
                                    :oidc_client_id     => oidc_client_id,
                                    :oidc_client_secret => oidc_client_secret,
                                    :oidc_enable_sso    => true)

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY,
                                                      "manageiq-external-auth-openidc.conf.erb",
                                                      :miq_appliance               => alternate_client_host,
                                                      :oidc_client_id              => oidc_client_id,
                                                      :oidc_client_secret          => oidc_client_secret,
                                                      :oidc_introspection_endpoint => oidc_introspection,
                                                      :oidc_provider_metadata_url  => oidc_url).and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to OpenID-Connect ...")
      expect(subject).to receive(:say).with("Configuring OpenID-Connect Authentication for https://#{alternate_client_host} ...")

      expect(subject).to receive(:say).with("Restarting httpd ...")
      expect(subject.configure(alternate_client_host)).to eq(true)
    end
  end

  context "unconfiguring OpenID-Connect" do
    it "fails if OpenID-Connect is not currently configured" do
      subject = described_class.new({})
      allow(subject).to receive(:configured?).and_return(false)

      expect(subject).to receive(:say).with(/Appliance is not currently configured for OpenID-Connect/)
      expect(subject.unconfigure).to eq(false)
    end

    it "succeeds if OpenID-Connect is currently configured" do
      subject = described_class.new({})
      allow(subject).to receive(:configured?).and_return(true)

      allow(subject).to receive(:remove_file)
      expect(subject).to receive(:remove_file).with(described_class::HTTPD_CONFIG_DIRECTORY.join("manageiq-remote-user-openidc.conf")).and_return(true)
      expect(subject).to receive(:remove_file).with(described_class::HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-openidc.conf")).and_return(true)

      expect(subject).to receive(:say).with(/Unconfiguring OpenID-Connect Authentication .../)
      expect(subject).to receive(:say).with(/Setting Appliance Authentication Settings to Database .../)
      expect(subject.unconfigure).to eq(true)
    end
  end
end
