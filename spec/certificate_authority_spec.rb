describe ManageIQ::ApplianceConsole::CertificateAuthority do
  let(:host)  { "client.network.com" }
  let(:realm) { "NETWORK.COM" }
  subject { described_class.new(:ca_name => 'ipa', :hostname => host) }

  context "#status" do
    it "should have no status if no services called" do
      expect(subject.status_string).to eq("")
      expect(subject).to be_complete
    end

    it "should be waiting if status is waiting" do
      subject.http = :waiting
      expect(subject).not_to be_complete
      expect(subject.status_string).to eq("http: waiting")
    end

    it "should be complete if all statuses are complete" do
      subject.http = :complete
      expect(subject).to be_complete
      expect(subject.status_string).to eq("http: complete")
    end
  end

  context "#http" do
    before do
      subject.http = true
    end

    it "without ipa client should not install" do
      ipa_configured(false)
      expect { subject.activate }.to raise_error(ArgumentError, /ipa client/)
    end

    it "should configure http" do
      ipa_configured(true)
      expect_run(/getcert/, anything, response).at_least(3).times

      expect(LinuxAdmin::Service).to receive(:new).and_return(double("Service", :restart => true))
      expect(LinuxAdmin::Service).to receive(:new).and_return(double(:enable => double(:start => nil)))
      expect(FileUtils).to receive(:chmod).with(0o644, anything)
      allow(ManageIQ::ApplianceConsole::Certificate).to receive(:say)
      expect(subject).to receive(:say)
      subject.activate
      expect(subject.http).to eq(:complete)
      expect(subject.status_string).to eq("http: complete")
      expect(subject).to be_complete
    end
  end

  private

  def ipa_configured(ipa_client_installed)
    expect(ManageIQ::ApplianceConsole::ExternalHttpdAuthentication).to receive(:ipa_client_configured?)
      .and_return(ipa_client_installed)
  end

  def expect_not_run(cmd = nil, params = anything)
    expect(AwesomeSpawn).not_to receive(:run).tap { |stmt| stmt.with(cmd, params) if cmd }
  end

  def expect_run(cmd, params, *responses)
    expectation = receive(:run).and_return(*(responses.empty? ? response : responses))
    if :none == params
      expectation.with(cmd)
    elsif params == anything || params == {}
      expectation.with(cmd, params)
    else
      expectation.with(cmd, :params => params)
    end
    expect(AwesomeSpawn).to(expectation)
  end

  def response(ret_code = 0)
    double("CommandResult", :success? => ret_code == 0, :failure? => ret_code != 0, :exit_status => ret_code)
  end
end
