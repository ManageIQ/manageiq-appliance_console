require 'tempfile'

describe ManageIQ::ApplianceConsole::MessageClientConfiguration do
  let(:server_hostname) { "my-kafka-server.example.com" }
  let(:server_username) { "root" }
  let(:server_password) { "server_super_secret" }
  let(:username) { "admin" }
  let(:password) { "super_secret" }
  subject do
    described_class.new(:server_hostname => server_hostname,
                        :server_username => server_username,
                        :server_password => server_password,
                        :username        => username,
                        :password        => password)
  end

  before do
    @tmp_base_dir = Pathname.new(Dir.mktmpdir)
    @tmp_miq_config_dir = Pathname.new(Dir.mktmpdir)
    @this = ManageIQ::ApplianceConsole::MessageConfiguration
    stub_const("#{@this}::BASE_DIR", @tmp_base_dir)
    stub_const("#{@this}::LOGS_DIR", "#{@tmp_base_dir}/logs")
    stub_const("#{@this}::CONFIG_DIR", "#{@tmp_base_dir}/config")
    stub_const("#{@this}::SAMPLE_CONFIG_DIR", "#{@tmp_base_dir}/config-sample")
    stub_const("#{@this}::MIQ_CONFIG_DIR", "#{@tmp_base_dir}/config-sample")

    FileUtils.mkdir_p("#{@tmp_base_dir}/config")
    FileUtils.mkdir_p("#{@tmp_base_dir}/config-sample")
  end

  after do
    FileUtils.rm_rf(@tmp_base_dir)
    FileUtils.rm_rf(@tmp_miq_config_dir)
  end

  describe "#ask_questions" do
    before do
      allow(subject).to receive(:agree).and_return(true)
      allow(subject).to receive(:host_reachable?).and_return(true)
      allow(subject).to receive(:message_client_configured?).and_return(false)
    end

    it "should prompt for Username and Password" do
      expect(subject).to receive(:ask_for_string).with("Message Key Username", username).and_return("admin")
      expect(subject).to receive(:ask_for_password).with("Message Key Password").and_return("top_secret")

      expect(subject).to receive(:ask_for_string).with("Message Server Hostname").and_return(server_hostname)
      expect(subject).to receive(:ask_for_string).with("Message Server Username", server_username).and_return("root")
      expect(subject).to receive(:ask_for_password).with("Message Server Password").and_return("top_secret")

      expect(subject).to receive(:say).at_least(5).times

      expect(subject.send(:ask_questions)).to be_truthy
    end

    it "should display Server Hostname and Key Username" do
      allow(subject).to receive(:ask_for_string).with("Message Key Username", username).and_return("admin")
      allow(subject).to receive(:ask_for_password).with("Message Key Password").and_return("top_secret")

      allow(subject).to receive(:ask_for_string).with("Message Server Hostname").and_return(server_hostname)
      allow(subject).to receive(:ask_for_string).with("Message Server Username", server_username).and_return("root")
      allow(subject).to receive(:ask_for_password).with("Message Server Password").and_return("top_secret")

      expect(subject).to receive(:say).with("\nMessage Client Parameters:\n\n")
      expect(subject).to receive(:say).with("\nMessage Client Configuration:\n")
      expect(subject).to receive(:say).with("Message Client Details:\n")
      expect(subject).to receive(:say).with("  Message Server Hostname:   my-kafka-server.example.com\n")
      expect(subject).to receive(:say).with("  Message Server Username:   root\n")
      expect(subject).to receive(:say).with("  Message Key Username:      admin\n")

      expect(subject.send(:ask_questions)).to be_truthy
    end
  end

  describe "#create_client_properties" do
    before do
      expect(subject).to receive(:say).with("Create Client Properties")
    end

    it "creates the client properties config file" do
      expect(subject.send(:create_client_properties)).to be_positive
      expect(subject.client_properties_path).to exist
    end

    it "correctly populates the client properties config file" do
      content = <<~CLIENT_PROPERTIES
        ssl.truststore.location=#{subject.truststore_path}
        ssl.truststore.password=#{password}

        sasl.mechanism=PLAIN
        security.protocol=SASL_SSL
        sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
          username=#{username} \\
          password=#{password} ;
      CLIENT_PROPERTIES

      expect(File).to receive(:write).with(subject.client_properties_path, content)
      expect(subject.send(:create_client_properties)).to be_nil
    end

    it "does not recreate the client properties config file if it already exists" do
      expect(subject).to receive(:say)
      FileUtils.touch(subject.client_properties_path)
      expect(File).not_to receive(:write)
      expect(subject.send(:create_client_properties)).to be_nil
    end
  end

  describe "#configure_messaging_yaml" do
    before do
      content = <<~MESSAGING_KAFKA_YML
        ---
        base: &base
          hostname: localhost
          port: 9092
          username: admin
          password: smartvm

        development:
          <<: *base

        production:
          <<: *base

        test:
          <<: *base
      MESSAGING_KAFKA_YML

      File.write(subject.messaging_yaml_sample_path, content)
      expect(subject).to receive(:say).with("Configure Messaging Yaml")
    end

    it "creates the messaging yaml file" do
      expect(subject.send(:configure_messaging_yaml)).to be_positive
      expect(subject.messaging_yaml_path).to exist
    end

    it "correctly populates the messaging yaml file" do
      content = <<~MESSAGING_YML
        ---
        base:
          hostname: localhost
          port: 9092
          username: admin
          password: smartvm
        development:
          hostname: localhost
          port: 9092
          username: admin
          password: smartvm
        production:
          hostname: my-kafka-server.example.com
          port: 9093
          username: admin
          password: #{ManageIQ::Password.try_encrypt("super_secret")}
        test:
          hostname: localhost
          port: 9092
          username: admin
          password: smartvm
      MESSAGING_YML

      expect(File).to receive(:write).with(subject.messaging_yaml_path, content)
      expect(subject.send(:configure_messaging_yaml)).to be_nil
    end

    it "does not recreate the messaging yaml file it already exists" do
      expect(subject).to receive(:say)
      FileUtils.touch(subject.messaging_yaml_path)
      expect(YAML).not_to receive(:load_file)
      expect(subject.send(:configure_messaging_yaml)).to be_nil
    end
  end

  describe "#fetch_truststore_from_server" do
    before do
      expect(subject).to receive(:say).with("Fetch Truststore From Server")
    end

    it "fetches the truststore from the server" do
      scp = double('scp')
      expect(scp).to receive(:download!).with(subject.truststore_path, subject.truststore_path).and_return(:result)
      expect(Net::SCP).to receive(:start).with(server_hostname, server_username, :password => server_password).and_yield(scp).and_return(true)
      subject.send(:fetch_truststore_from_server)
    end

    it "does not recreate the keystore directory if it already exists" do
      expect(subject).to receive(:say)
      FileUtils.mkdir_p(subject.keystore_dir_path)
      FileUtils.touch(subject.truststore_path)

      expect(FileUtils).not_to receive(:mkdir_p)
      expect(subject.send(:fetch_truststore_from_server)).to be_nil
    end
  end

  describe "#restart_evmserverd" do
    it "restarts evmserverd if it is running" do
      expect(subject).to receive(:say)
      expect(LinuxAdmin::Service).to receive(:new).with("evmserverd").and_return(double(@spec_name, :running? => true, :restart => nil))
      expect(subject.send(:restart_evmserverd)).to be_nil
    end

    it "does not restart evmserverd if it is not running" do
      expect(subject).to receive(:say)
      expect(LinuxAdmin::Service).to receive(:new).with("evmserverd").and_return(double(@spec_name, :running? => false))
      expect(subject.send(:restart_evmserverd)).to be_nil
    end
  end
end
