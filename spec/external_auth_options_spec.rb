describe ManageIQ::ApplianceConsole::ExternalAuthOptions do
  subject { described_class.new }
  let(:result) { double("RakeResult", :failure? => false) }
  let(:rake_set) { "evm:settings:set" }

  before do
    allow(subject).to receive(:say)
  end

  context "#update_configuration" do
    it "will toggle SSO when provided alone" do
      sso_alone = {"/authentication/sso_enabled" => true}
      expected_params = sso_alone.collect { |key, value| "#{key}=#{value}" }
      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with(rake_set, expected_params).and_return(result)
      subject.update_configuration(sso_alone)
    end

    it "will toggle SSO when provided with provider type oidc" do
      sso_with_oidc = {"/authentication/sso_enabled" => true, "/authentication/oidc_enabled" => true}
      expected_params = sso_with_oidc.collect { |key, value| "#{key}=#{value}" }
      expected_params << "/authentication/saml_enabled=false"
      expected_params << "/authentication/provider_type=oidc"

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with(rake_set, expected_params).and_return(result)
      subject.update_configuration(sso_with_oidc)
    end

    it "will toggle Local Login when provided alone" do
      loacl_login_alone = {"/authentication/local_login_disabled" => true}
      expected_params = loacl_login_alone.collect { |key, value| "#{key}=#{value}" }
      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with(rake_set, expected_params).and_return(result)
      subject.update_configuration(loacl_login_alone)
    end

    it "will set provider type oidc" do
      oidc = {"/authentication/oidc_enabled" => true}
      expected_params = oidc.collect { |key, value| "#{key}=#{value}" }
      expected_params << "/authentication/saml_enabled=false"
      expected_params << "/authentication/provider_type=oidc"

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with(rake_set, expected_params).and_return(result)
      subject.update_configuration(oidc)
    end

    it "will set provider type saml" do
      saml = {"/authentication/saml_enabled" => true}
      expected_params = saml.collect { |key, value| "#{key}=#{value}" }
      expected_params << "/authentication/oidc_enabled=false"
      expected_params << "/authentication/provider_type=saml"

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with(rake_set, expected_params).and_return(result)
      subject.update_configuration(saml)
    end

    it "will set provider type none" do
      none = {"/authentication/saml_enabled" => false, "/authentication/oidc_enabled" => false}
      expected_params = none.collect { |key, value| "#{key}=#{value}" }
      expected_params << "/authentication/oidc_enabled=false"
      expected_params << "/authentication/saml_enabled=false"
      expected_params << "/authentication/provider_type=none"

      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake_run).with(rake_set, expected_params).and_return(result)
      subject.update_configuration(none)
    end
  end
end
