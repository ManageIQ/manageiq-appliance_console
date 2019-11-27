describe ManageIQ::ApplianceConsole::OpenIDCAuthentication do
  let(:client_host) { "client.example.com" }
  let(:openidc_url) { "http://openidc.example.com:8080/auth/realms/manageiq/.well-known/openid-configuration" }

  context "configuring OpenID-Connect" do
    it "fails without the openidc-url option specified" do
      subject = described_class.new({})

      expect(subject).to receive(:say).with(/Must specify the OpenID-Connect Provider URL via --openidc-url/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "fails without the openidc-client-id option specified" do
      subject = described_class.new(:openidc_url => openidc_url)

      expect(subject).to receive(:say).with(/Must specify the OpenID-Connect Client ID via --openidc-client-id/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "fails without the openidc-client-secret option specified" do
      subject = described_class.new(:openidc_url => "http://openidc.provider.example.com", :openidc_client_id => "https://#{client_host}")

      expect(subject).to receive(:say).with(/Must specify the OpenID-Connect Client Secret via --openidc-client-secret/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "succeeds with provider url, client id and secret specified and restarts httpd" do
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

      openidc_client_id = "https://#{client_host}"
      openidc_client_secret = "17106c0d-8446-4b87-82e4-b7408ad583d0"
      subject = described_class.new(:openidc_url => openidc_url, :openidc_client_id => openidc_client_id, :openidc_client_secret => openidc_client_secret)

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY,
                                                      "manageiq-external-auth-openidc.conf.erb",
                                                      :miq_appliance              => client_host,
                                                      :oidc_client_id             => openidc_client_id,
                                                      :oidc_client_secret         => openidc_client_secret,
                                                      :oidc_provider_metadata_url => openidc_url).and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to OpenID-Connect ...")
      expect(subject).to receive(:say).with("Configuring OpenID-Connect Authentication for https://#{client_host} ...")

      expect(subject).to receive(:say).with("Restarting httpd ...")
      expect(subject.configure(client_host)).to eq(true)
    end

    it "succeeds with client host, enabling SSO, and restarts httpd" do
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
      openidc_client_id = "https://altern#{alternate_client_host}"
      openidc_client_secret = "18106c0d-8456-4b87-83e5-c74a9ad583e0"
      subject = described_class.new(:openidc_url           => openidc_url,
                                    :openidc_client_id     => openidc_client_id,
                                    :openidc_client_secret => openidc_client_secret,
                                    :openidc_enable_sso    => true)

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-openidc.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY,
                                                      "manageiq-external-auth-openidc.conf.erb",
                                                      :miq_appliance              => alternate_client_host,
                                                      :oidc_client_id             => openidc_client_id,
                                                      :oidc_client_secret         => openidc_client_secret,
                                                      :oidc_provider_metadata_url => openidc_url).and_return(true)

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
