describe ManageIQ::ApplianceConsole::Principal do
  before { expect(Open3).not_to receive(:capture3) }
  let(:hostname) { "machine.network.com" }
  let(:realm)    { "NETWORK.COM" }
  let(:service)  { "postgres" }
  let(:service_principal)  { "postgres/machine.network.com" }
  let(:kerberos_principal) { "postgres/machine.network.com@NETWORK.COM" }

  subject { described_class.new(:hostname => hostname, :realm => realm, :service => service) }

  it { expect(subject.hostname).to eq(hostname) }
  it { expect(subject.realm).to eq(realm) }
  it { expect(subject.service).to eq(service) }

  it { expect(subject.name).to eq(kerberos_principal) }
  it { expect(subject.subject_name).to match(/CN=#{hostname}.*O=#{realm}/) }
  it { expect(subject).to be_ipa }

  it "should register if not yet registered" do
    expect_run(/ipa/, ["-e", "skip_version_check=1", "service-find", "--principal", service_principal], response(1))
    expect_run(/ipa/, ["-e", "skip_version_check=1", "service-add", "--force", service_principal], response)

    subject.register
  end

  it "should not register if already registered" do
    expect_run(/ipa/, ["-e", "skip_version_check=1", "service-find", "--principal", service_principal], response)

    subject.register
  end

  it "should not register if not ipa" do
    subject.ca_name = "other"
    subject.register
  end

  private

  def expect_run(cmd, params, *responses)
    expect(AwesomeSpawn).to receive(:run).with(cmd, {:params => params})
      .and_return(*(responses.empty? ? response : responses))
  end

  def response(ret_code = 0)
    AwesomeSpawn::CommandResult.new("cmd", "output", "", nil, ret_code)
  end
end
