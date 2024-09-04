describe ManageIQ::ApplianceConsole::SamlAuthentication do
  let(:client_host) { "client.example.com" }

  context "configuring SAML" do
    it "fails without idp metadata option specified" do
      subject = described_class.new({})

      expect(subject).to receive(:say).with(/Must specify the SAML IDP metadata file or URL via --saml-idp-metadata/)
      expect(subject.configure(client_host)).to eq(false)
    end

    it "fails if idp metadata file specified does not exist" do
      downloaded_idp_metadata = "/tmp/invalid_idp_metadata.xml"
      subject = described_class.new(:saml_idp_metadata => downloaded_idp_metadata)

      expect(File).to receive(:exist?).with(downloaded_idp_metadata).and_return(false)
      expect(subject).to receive(:say).with(%r{Missing SAML IDP metadata file /tmp/invalid_idp_metadata.xml})
      expect(subject.configure(client_host)).to eq(false)
    end

    it "succeeds with downloaded idp metadata and restarts httpd" do
      httpd_service = double(@spec_name, :running? => true)
      expect(httpd_service).to receive(:restart)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(httpd_service)
      expect(FileUtils).to receive(:mkdir_p).with(described_class::SAML2_CONFIG_DIRECTORY).and_return(true)

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with("evm:settings:set",
                                                                               ["/authentication/mode=httpd",
                                                                                "/authentication/httpd_role=true",
                                                                                "/authentication/saml_enabled=true",
                                                                                "/authentication/oidc_enabled=false",
                                                                                "/authentication/sso_enabled=false",
                                                                                "/authentication/provider_type=saml"])

      downloaded_idp_metadata = "/tmp/downloaded_idp_metadata.xml"
      subject = described_class.new(:saml_idp_metadata => downloaded_idp_metadata)

      expect(File).to receive(:exist?).with(downloaded_idp_metadata).and_return(true)
      expect(FileUtils).to receive(:cp).with(downloaded_idp_metadata, described_class::IDP_METADATA_FILE).and_return(true)
      allow(Dir).to receive(:chdir).with(described_class::SAML2_CONFIG_DIRECTORY).and_yield
      expect(AwesomeSpawn).to receive(:run!).with(described_class::MELLON_CREATE_METADATA_COMMAND,
                                                  :chdir  => described_class::SAML2_CONFIG_DIRECTORY,
                                                  :params => ["https://#{client_host}", "https://#{client_host}/saml2"])

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-saml.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf").and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to SAML ...")
      expect(subject).to receive(:say).with("Configuring SAML Authentication for https://#{client_host} ...")

      expect(subject).to receive(:say).with("Restarting httpd ...")
      expect(subject.configure(client_host)).to eq(true)
    end

    it "succeeds with URL idp metadata" do
      httpd_service = double(@spec_name, :running? => false)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(httpd_service)
      expect(FileUtils).to receive(:mkdir_p).with(described_class::SAML2_CONFIG_DIRECTORY).and_return(true)

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with("evm:settings:set",
                                                                               ["/authentication/mode=httpd",
                                                                                "/authentication/httpd_role=true",
                                                                                "/authentication/saml_enabled=true",
                                                                                "/authentication/oidc_enabled=false",
                                                                                "/authentication/sso_enabled=false",
                                                                                "/authentication/provider_type=saml"])

      idp_metadata_url = "http://idp.example.com/idp_metadata.xml"
      subject = described_class.new(:saml_idp_metadata => idp_metadata_url)

      allow(Dir).to receive(:chdir).with(described_class::SAML2_CONFIG_DIRECTORY).and_yield
      expect(AwesomeSpawn).to receive(:run!).with(described_class::MELLON_CREATE_METADATA_COMMAND,
                                                  :chdir  => described_class::SAML2_CONFIG_DIRECTORY,
                                                  :params => ["https://#{client_host}", "https://#{client_host}/saml2"])

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-saml.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf").and_return(true)
      expect(subject).to receive(:download_network_file).with(idp_metadata_url, described_class::IDP_METADATA_FILE).and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to SAML ...")
      expect(subject).to receive(:say).with("Configuring SAML Authentication for https://#{client_host} ...")
      expect(subject.configure(client_host)).to eq(true)
    end

    it "succeeds with downloaded idp metadata with optional client host and enabling SSO" do
      alternate_client_host = "alternate.client.example.com"

      httpd_service = double(@spec_name, :running? => false)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(httpd_service)
      expect(FileUtils).to receive(:mkdir_p).with(described_class::SAML2_CONFIG_DIRECTORY).and_return(true)

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with("evm:settings:set",
                                                                               ["/authentication/mode=httpd",
                                                                                "/authentication/httpd_role=true",
                                                                                "/authentication/saml_enabled=true",
                                                                                "/authentication/oidc_enabled=false",
                                                                                "/authentication/sso_enabled=true",
                                                                                "/authentication/provider_type=saml"])

      downloaded_idp_metadata = "/tmp/downloaded_idp_metadata.xml"
      subject = described_class.new(:saml_idp_metadata => downloaded_idp_metadata,
                                    :saml_client_host  => alternate_client_host,
                                    :saml_enable_sso   => true)

      expect(File).to receive(:exist?).with(downloaded_idp_metadata).and_return(true)
      allow(Dir).to receive(:chdir).with(described_class::SAML2_CONFIG_DIRECTORY).and_yield
      expect(AwesomeSpawn).to receive(:run!).with(described_class::MELLON_CREATE_METADATA_COMMAND,
                                                  :chdir  => described_class::SAML2_CONFIG_DIRECTORY,
                                                  :params => ["https://#{alternate_client_host}", "https://#{alternate_client_host}/saml2"])

      expect(FileUtils).to receive(:cp).with(downloaded_idp_metadata, described_class::IDP_METADATA_FILE).and_return(true)

      allow(subject).to receive(:copy_template)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-remote-user-saml.conf").and_return(true)
      expect(subject).to receive(:copy_template).with(described_class::HTTPD_CONFIG_DIRECTORY, "manageiq-external-auth-saml.conf").and_return(true)

      expect(subject).to receive(:say).with("Setting Appliance Authentication Settings to SAML ...")
      expect(subject).to receive(:say).with("Configuring SAML Authentication for https://#{alternate_client_host} ...")
      expect(subject.configure(alternate_client_host)).to eq(true)
    end
  end

  context "unconfiguring SAML" do
    it "fails if SAML is not currently configured" do
      subject = described_class.new({})
      allow(subject).to receive(:configured?).and_return(false)

      expect(subject).to receive(:say).with(/Appliance is not currently configured for SAML/)
      expect(subject.unconfigure).to eq(false)
    end

    it "succeeds if SAML is currently configured" do
      subject = described_class.new({})
      allow(subject).to receive(:configured?).and_return(true)

      allow(subject).to receive(:remove_file)
      expect(subject).to receive(:remove_file).with(described_class::HTTPD_CONFIG_DIRECTORY.join("manageiq-external-auth-saml.conf")).and_return(true)
      expect(subject).to receive(:remove_file).with(described_class::HTTPD_CONFIG_DIRECTORY.join("manageiq-remote-user.conf")).and_return(true)
      expect(subject).to receive(:remove_file).with(described_class::HTTPD_CONFIG_DIRECTORY.join("manageiq-remote-user-saml.conf")).and_return(true)

      expect(subject).to receive(:say).with(/Unconfiguring SAML Authentication .../)
      expect(subject).to receive(:say).with(/Setting Appliance Authentication Settings to Database .../)
      expect(subject.unconfigure).to eq(true)
    end
  end
end
