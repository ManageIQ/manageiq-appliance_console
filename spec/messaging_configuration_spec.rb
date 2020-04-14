describe ManageIQ::ApplianceConsole::MessagingConfiguration do
  context "#ask_for_messaging_credentials" do
    it "success" do
      expect(subject).to receive(:just_ask).with(/messaging hostname or IP address/i, anything, anything, anything).and_return("server.example.com")
      expect(subject).to receive(:just_ask).with(/port/i, anything, anything, anything, anything).and_return("9092")
      expect(subject).to receive(:just_ask).with(/username/i).and_return("x")
      expect(subject).to receive(:just_ask).with(/password/i, anything).twice.and_return("the password")

      subject.ask_for_messaging_credentials

      expect(subject).to have_attributes(
        :host     => "server.example.com",
        :password => "the password",
        :port     => 9092,
        :username => "x"
      )
    end

    it "password doesn't match" do
      expect(subject).to receive(:just_ask).with(/messaging hostname or IP address/i, anything, anything, anything).and_return("server.example.com")
      expect(subject).to receive(:just_ask).with(/port/i, anything, anything, anything, anything).and_return("9092")
      expect(subject).to receive(:just_ask).with(/username/i).and_return("x")
      expect(subject).to receive(:just_ask).with(/password/i, anything).and_return("the password", "abc", "the password", "xyz")

      expect(STDOUT).to receive(:puts).with(/did not match/)

      expect { subject.ask_for_messaging_credentials }.to raise_error(RuntimeError, "passwords did not match")
    end

    it "password empty will retry until valid" do
      expect(subject).to receive(:just_ask).with(/messaging hostname or IP address/i, anything, anything, anything).and_return("server.example.com")
      expect(subject).to receive(:just_ask).with(/port/i, anything, anything, anything, anything).and_return("9092")
      expect(subject).to receive(:just_ask).with(/username/i).and_return("x")
      expect(subject).to receive(:just_ask).with(/password/i, anything).and_return("   ", "", "xyz", "xyz")

      expect(STDOUT).to receive(:puts).with(/can not be empty/).twice

      subject.ask_for_messaging_credentials
    end
  end

  it "#save encrypts the password" do
    subject.host     = "abc.example.com"
    subject.password = "abc123"
    subject.port     = 9092
    subject.username = "admin"

    expected_string = <<~EXPECTED
      ---
      production:
        hostname: abc.example.com
        port: 9092
        username: admin
        password: v2:{7dUJhm+whBC1Y2Bn1Kf+Ug==}
    EXPECTED

    expect(File).to receive(:write).with(anything, expected_string)

    subject.send(:save)
  end
end
