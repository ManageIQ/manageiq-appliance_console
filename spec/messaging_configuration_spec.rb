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
end
