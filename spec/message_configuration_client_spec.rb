require 'tempfile'

describe ManageIQ::ApplianceConsole::MessageClientConfiguration do
  let(:message_server_host) { "my-kafka-server.example.com" }
  let(:message_server_username) { "root" }
  let(:message_server_password) { "server_super_secret" }
  let(:message_keystore_username) { "admin" }
  let(:message_keystore_password) { "super_secret" }
  subject do
    described_class.new(:message_server_host       => message_server_host,
                        :message_server_port       => 9_093,
                        :message_server_username   => message_server_username,
                        :message_server_password   => message_server_password,
                        :message_keystore_username => message_keystore_username,
                        :message_keystore_password => message_keystore_password)
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

    allow(Process::UID).to receive(:from_name).with("manageiq").and_return(Process.uid)
    allow(Process::GID).to receive(:from_name).with("manageiq").and_return(Process.gid)
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

    it "should prompt for message_keystore_username and message_keystore_password" do
      expect(subject).to receive(:ask_for_string).with("Message Server Hostname or IP address").and_return("my-host-name.example.com")
      expect(subject).to receive(:ask_for_integer).with("Message Server Port number", (1..65_535), 9_093).and_return("9093")
      expect(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
      expect(subject).to receive(:ask_for_password).with("Message Keystore Password").and_return("top_secret")
      expect(subject).to receive(:ask_for_string).with("Message Server Truststore Path", subject.truststore_path)
      expect(subject).to receive(:ask_for_string).with("Message Server CA Cert Path", subject.ca_cert_path)

      expect(subject).to receive(:ask_for_string).with("Message Server Username", message_server_username).and_return("root")
      expect(subject).to receive(:ask_for_password).with("Message Server Password").and_return("top_secret")

      expect(subject).to receive(:say).at_least(5).times

      expect(subject.send(:ask_questions)).to be_truthy
    end

    it "should display Server Hostname and Key Username" do
      allow(subject).to receive(:ask_for_string).with("Message Server Hostname or IP address").and_return("my-kafka-server.example.com")
      allow(subject).to receive(:ask_for_integer).with("Message Server Port number", (1..65_535), 9_093).and_return("9093")
      allow(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
      allow(subject).to receive(:ask_for_password).with("Message Keystore Password").and_return("top_secret")
      allow(subject).to receive(:ask_for_string).with("Message Server Truststore Path", subject.truststore_path)
      allow(subject).to receive(:ask_for_string).with("Message Server CA Cert Path", subject.ca_cert_path)

      allow(subject).to receive(:ask_for_string).with("Message Server Username", message_server_username).and_return("root")
      allow(subject).to receive(:ask_for_password).with("Message Server Password").and_return("top_secret")

      expect(subject).to receive(:say).with("\nMessage Client Parameters:\n\n")
      expect(subject).to receive(:say).with("\nMessage Client Configuration:\n")
      expect(subject).to receive(:say).with("Message Client Details:\n")
      expect(subject).to receive(:say).with("  Message Server Hostname:   my-kafka-server.example.com\n")
      expect(subject).to receive(:say).with("  Message Server Username:   root\n")
      expect(subject).to receive(:say).with("  Message Keystore Username: admin\n")

      expect(subject.send(:ask_questions)).to be_truthy
    end
  end

  describe "#create_client_properties" do
    subject do
      described_class.new(:message_server_host       => message_server_host,
                          :message_server_port       => message_server_port,
                          :message_server_username   => message_server_username,
                          :message_server_password   => message_server_password,
                          :message_keystore_username => message_keystore_username,
                          :message_keystore_password => message_keystore_password)
    end

    let(:secure_content) do
      <<~CLIENT_PROPERTIES
        ssl.endpoint.identification.algorithm=#{ident_algorithm}

        sasl.mechanism=PLAIN
        security.protocol=#{security_protocol}
        sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
          username=#{message_keystore_username} \\
          password=#{message_keystore_password} ;
        ssl.truststore.location=#{subject.truststore_path}
        ssl.truststore.password=#{message_keystore_password}
      CLIENT_PROPERTIES
    end

    let(:unsecure_content) do
      <<~CLIENT_PROPERTIES
        ssl.endpoint.identification.algorithm=#{ident_algorithm}

        sasl.mechanism=PLAIN
        security.protocol=#{security_protocol}
        sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
          username=#{message_keystore_username} \\
          password=#{message_keystore_password} ;
      CLIENT_PROPERTIES
    end

    shared_examples "client properties config file" do
      it "creates the client properties config file" do
        expect(subject.send(:create_client_properties)).to be_positive
        expect(subject.client_properties_path).to exist
      end

      it "does not recreate the client properties config file if it already exists" do
        expect(subject).to receive(:say)
        FileUtils.touch(subject.client_properties_path)
        expect(File).not_to receive(:write)
        expect(subject.send(:create_client_properties)).to be_nil
      end

      it "correctly populates the client properties config file" do
        expect(File).to receive(:write).with(subject.client_properties_path, content)
        expect(subject.send(:create_client_properties)).to be_nil
      end
    end

    before do
      expect(subject).to receive(:say).with("Create Client Properties")
    end

    context "secure with hostname" do
      let(:message_server_port) { 9_093 }
      let(:message_server_host) { "my-kafka-server.example.com" }
      let(:ident_algorithm) { "HTTPS" }
      let(:security_protocol) { "SASL_SSL" }
      let(:content) { secure_content }

      include_examples "client properties config file"
    end

    context "secure with IP address" do
      let(:message_server_port) { 9_093 }
      let(:message_server_host) { "192.0.2.0" }
      let(:ident_algorithm) { "" }
      let(:security_protocol) { "SASL_SSL" }
      let(:content) { secure_content }

      include_examples "client properties config file"
    end

    context "unsecure with hostname" do
      let(:message_server_port) { 9_092 }
      let(:message_server_host) { "my-kafka-server.example.com" }
      let(:ident_algorithm) { "HTTPS" }
      let(:security_protocol) { "PLAINTEXT" }
      let(:content) { unsecure_content }

      include_examples "client properties config file"
    end

    context "unsecure with IP address" do
      let(:message_server_port) { 9_092 }
      let(:message_server_host) { "192.0.2.0" }
      let(:ident_algorithm) { "" }
      let(:security_protocol) { "PLAINTEXT" }
      let(:content) { unsecure_content }

      include_examples "client properties config file"
    end
  end

  describe "#configure_messaging_yaml" do
    subject do
      described_class.new(:message_server_host       => message_server_host,
                          :message_server_port       => message_server_port,
                          :message_server_username   => message_server_username,
                          :message_server_password   => message_server_password,
                          :message_keystore_username => message_keystore_username,
                          :message_keystore_password => message_keystore_password)
    end

    let(:messagine_kafka_yml_content) do
      <<~MESSAGING_KAFKA_YML
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
    end

    let(:secure_messagine_yml_content) do
      <<~SECURE_MESSAGING_YML
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
          sasl.mechanism: PLAIN
          sasl.username: admin
          sasl.password: #{ManageIQ::Password.try_encrypt("super_secret")}
          security.protocol: SASL_SSL
          ssl.ca.location: "#{@tmp_base_dir}/config/keystore/ca-cert"
        test:
          hostname: localhost
          port: 9092
          username: admin
          password: smartvm
      SECURE_MESSAGING_YML
    end

    let(:unsecure_messagine_yml_content) do
      <<~UNSECURE_MESSAGING_YML
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
          port: 9092
          sasl.mechanism: PLAIN
          sasl.username: admin
          sasl.password: #{ManageIQ::Password.try_encrypt("super_secret")}
          security.protocol: PLAINTEXT
        test:
          hostname: localhost
          port: 9092
          username: admin
          password: smartvm
      UNSECURE_MESSAGING_YML
    end

    shared_examples "messaging yaml file" do
      it "creates the messaging yaml file" do
        subject.send(:configure_messaging_yaml)
        expect(subject.messaging_yaml_path).to exist
      end

      it "does not recreate the messaging yaml file it already exists" do
        expect(subject).to receive(:say)
        FileUtils.touch(subject.messaging_yaml_path)
        expect(YAML).not_to receive(:load_file)
        expect(subject.send(:configure_messaging_yaml)).to be_nil
      end

      it "correctly populates the messaging yaml file" do
        allow(File).to receive(:open).and_call_original

        file_stub = double("File")
        expect(File).to receive(:open).with(subject.messaging_yaml_path, "w").and_yield(file_stub)
        expect(file_stub).to receive(:write).with(content)
        expect(file_stub).to receive(:chown).with(Process.uid, Process.gid)
        expect(subject.send(:configure_messaging_yaml)).to be_nil
      end
    end

    before do
      expect(subject).to receive(:say).with("Configure Messaging Yaml")
      File.write(subject.messaging_yaml_sample_path, messagine_kafka_yml_content)
    end

    context "when using secure port 9093" do
      let(:content) { secure_messagine_yml_content }
      let(:message_server_port) { 9_093 }
      include_examples "messaging yaml file"
    end

    context "when using unsecure port 9092" do
      let(:content) { unsecure_messagine_yml_content }
      let(:message_server_port) { 9_092 }
      include_examples "messaging yaml file"
    end
  end

  describe "#fetch_truststore_from_server" do
    before do
      expect(subject).to receive(:say).with("Fetch Truststore From Server")
    end

    it "fetches the truststore from the server" do
      scp = double('scp')
      expect(scp).to receive(:download!).with(subject.truststore_path, subject.truststore_path).and_return(:result)
      expect(Net::SCP).to receive(:start).with(message_server_host, message_server_username, :password => message_server_password).and_yield(scp).and_return(true)
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
end
