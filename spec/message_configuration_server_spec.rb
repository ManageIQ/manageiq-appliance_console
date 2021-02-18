require 'tempfile'

describe ManageIQ::ApplianceConsole::MessageServerConfiguration do
  let(:message_keystore_username) { "admin" }
  let(:message_keystore_password) { "super_secret" }
  subject { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password) }
  let(:subject_ip) { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password, :message_server_host => "192.0.2.0") }

  before do
    @spec_name = File.basename(__FILE__).split(".rb").first.freeze
    @tmp_base_dir = Pathname.new(Dir.mktmpdir)
    @tmp_miq_config_dir = Pathname.new(Dir.mktmpdir)
    @this = ManageIQ::ApplianceConsole::MessageConfiguration
    @keystore_path = Pathname.new("#{@tmp_base_dir}/config/keystore/keystore.jks")
    stub_const("#{@this}::BASE_DIR", @tmp_base_dir)
    stub_const("#{@this}::LOGS_DIR", "#{@tmp_base_dir}/logs")
    stub_const("#{@this}::CONFIG_DIR", "#{@tmp_base_dir}/config")
    stub_const("#{@this}::SAMPLE_CONFIG_DIR", "#{@tmp_base_dir}/config-sample")
    stub_const("#{@this}::MIQ_CONFIG_DIR", "#{@tmp_base_dir}/config-sample")

    FileUtils.mkdir_p("#{@tmp_base_dir}/config/keystore")
    FileUtils.mkdir_p("#{@tmp_base_dir}/config-sample")

    allow_any_instance_of(LinuxAdmin::Hosts).to receive(:hostname).and_return('my-host-name.example.com')
  end

  after do
    FileUtils.rm_rf(@tmp_base_dir)
    FileUtils.rm_rf(@tmp_miq_config_dir)
  end

  describe "#ask_questions" do
    before do
      allow(subject).to receive(:agree).and_return(true)
      allow(subject).to receive(:host_reachable?).and_return(true)
      allow(subject).to receive(:message_server_configured?).and_return(false)
    end

    it "should prompt for message_keystore_Username and message_keystore_Password" do
      expect(subject).to receive(:ask_for_string).with("Message Server Hostname or IP address", "my-host-name.example.com").and_return("my-host-name.example.com")
      expect(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
      expect(subject).to receive(:ask_for_password).with("Message Keystore Password").and_return("top_secret")

      allow(subject).to receive(:say).at_least(5).times

      expect(subject.send(:ask_questions)).to be_truthy
    end

    it "should display Server Hostname and Keystore Username" do
      allow(subject).to receive(:ask_for_string).with("Message Server Hostname or IP address", "my-host-name.example.com").and_return("my-host-name.example.com")
      allow(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
      allow(subject).to receive(:ask_for_password).with("Message Keystore Password").and_return("top_secret")

      expect(subject).to receive(:say).with("\nMessage Server Parameters:\n\n")
      expect(subject).to receive(:say).with("\nMessage Server Configuration:\n")
      expect(subject).to receive(:say).with("Message Server Details:\n")
      expect(subject).to receive(:say).with("  Message Server Hostname:   my-host-name.example.com\n")
      expect(subject).to receive(:say).with("  Message Keystore Username: admin\n")

      expect(subject.send(:ask_questions)).to be_truthy
    end
  end

  describe "#create_jaas_config" do
    before do
      expect(subject).to receive(:say).with("Create Jaas Config")
    end

    it "creates the jaas config file" do
      expect(subject.send(:create_jaas_config)).to be_positive
      expect(subject.jaas_config_path).to exist
    end

    it "correctly populates the jaas config file" do
      content = <<~JAAS
        KafkaServer {
          org.apache.kafka.common.security.plain.PlainLoginModule required
          username=#{message_keystore_username}
          password=#{message_keystore_password}
          user_admin=#{message_keystore_password} ;
        };
      JAAS

      expect(File).to receive(:write).with(subject.jaas_config_path, content)
      expect(subject.send(:create_jaas_config)).to be_nil
    end

    it "does not recreate the jaas config file if it already exists" do
      expect(subject).to receive(:say)
      FileUtils.touch(subject.jaas_config_path)
      expect(File).not_to receive(:write)
      expect(subject.send(:create_jaas_config)).to be_nil
    end
  end

  describe "#create_logs_directory" do
    before do
      expect(subject).to receive(:say).with("Create Logs Directory")
    end

    it "creates the logs directory" do
      expect(FileUtils).to receive(:chown).with("kafka", "kafka", @this::LOGS_DIR)
      expect(subject.send(:create_logs_directory)).to be_nil
      expect(File.directory?(@this::LOGS_DIR)).to be_truthy
    end

    it "does not recreate the logs directory if it already exists" do
      expect(subject).to receive(:say)
      FileUtils.touch(@this::LOGS_DIR)
      expect(FileUtils).not_to receive(:mkdir)
      expect(subject.send(:create_logs_directory)).to be_nil
    end
  end

  describe "#configure_firewall" do
    before do
      expect(subject).to receive(:say).with("Configure Firewall")
    end

    it "will issue the firewall commands to add the kafka ports" do
      expect(AwesomeSpawn).to receive(:run!).with("firewall-cmd", {:params => {:add_port => "9093/tcp", :permanent => nil}})

      expect(AwesomeSpawn).to receive(:run!).with("firewall-cmd --reload")
      expect(subject.send(:configure_firewall)).to be_nil
    end
  end

  describe "#configure_keystore" do
    subject { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password, :message_server_host => message_server_host) }

    shared_examples "configure keystore" do
      it "creates and populates the keystore directory" do
        allow(AwesomeSpawn).to receive(:run!).exactly(7).times

        expect(AwesomeSpawn).to receive(:run!)
          .with("keytool",
                :params => {"-keystore"  => @keystore_path,
                            "-validity"  => 10_000,
                            "-genkey"    => nil,
                            "-keyalg"    => "RSA",
                            "-storepass" => message_keystore_password,
                            "-keypass"   => message_keystore_password,
                            "-alias"     => ks_alias,
                            "-dname"     => "cn=#{ks_alias}",
                            "-ext"       => ext})
        expect(subject.send(:configure_keystore)).to be_nil
        expect(File.directory?(subject.keystore_dir_path)).to be_truthy
      end

      it "does not recreate the keystore files if they already exists" do
        subject.keystore_files.each { |f| FileUtils.touch(f) }
        expect(AwesomeSpawn).not_to receive(:run!)
        expect(subject).to receive(:say).exactly(7).times
        expect(subject.send(:configure_keystore)).to be_nil
      end
    end

    before do
      expect(subject).to receive(:say).with("Configure Keystore")
    end

    context "with IP address" do
      let(:ks_alias) { "localhost" }
      let(:message_server_host) { "192.0.2.0" }
      let(:ext) { "san=ip:#{message_server_host}" }

      include_examples "configure keystore"
    end

    context "with hostname" do
      let(:ks_alias) { "my-host-name.example.com" }
      let(:message_server_host) { ks_alias }
      let(:ext) { "san=dns:my-host-name.example.com" }

      include_examples "configure keystore"
    end
  end

  describe "#create_server_properties" do
    subject { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password, :message_server_host => message_server_host) }

    let(:content) do
      <<~SERVER_PROPERTIES

        listeners=SASL_SSL://:9093

        ssl.endpoint.identification.algorithm=#{ident_algorithm}
        ssl.keystore.location=#{subject.keystore_path}
        ssl.keystore.password=#{message_keystore_password}
        ssl.key.password=#{message_keystore_password}

        ssl.truststore.location=#{subject.truststore_path}
        ssl.truststore.password=#{message_keystore_password}

        ssl.client.auth=#{client_auth}

        sasl.enabled.mechanisms=PLAIN
        sasl.mechanism.inter.broker.protocol=PLAIN

        security.inter.broker.protocol=SASL_SSL
      SERVER_PROPERTIES
    end

    before do
      FileUtils.touch(subject.server_properties_sample_path)
      FileUtils.touch(subject.server_properties_path)

      expect(subject).to receive(:say).with("Create Server Properties")
    end

    shared_examples "service properties file" do
      it "creates the service properties config file" do
        expect(subject.send(:create_server_properties)).to be_positive
        expect(subject.server_properties_path).to exist
      end

      it "correctly populates the server properties config file" do
        expect(File).to receive(:write).with(subject.server_properties_path, content, :mode => "a")
        expect(subject.send(:create_server_properties)).to be_nil
      end

      it "does not recreate the server properties config file if it already exists" do
        expect(subject).to receive(:say)
        File.write(subject.server_properties_path, content, :mode => "a")
        expect(File).not_to receive(:write)
        expect(subject.send(:create_server_properties)).to be_nil
      end
    end

    context "with IP address" do
      let(:ident_algorithm) { "" }
      let(:client_auth) { "none" }
      let(:message_server_host) { "192.0.2.0" }
      include_examples "service properties file"
    end

    context "with hostname" do
      let(:ident_algorithm) { "HTTPS" }
      let(:client_auth) { "required" }
      let(:message_server_host) { "my-kafka-server.example.com" }
      include_examples "service properties file"
    end
  end

  describe "#restart_services" do
    before do
      expect(subject).to receive(:say).exactly(3).times
      @evmserverd = LinuxAdmin::Service.new("evmserverd")

      zookeeper = LinuxAdmin::Service.new("zookeeper")
      expect(zookeeper).to receive(:start).and_return(zookeeper)
      expect(zookeeper).to receive(:enable)

      kafka = LinuxAdmin::Service.new("kafka")
      expect(kafka).to receive(:start).and_return(kafka)
      expect(kafka).to receive(:enable)

      expect(LinuxAdmin::Service).to receive(:new).with("zookeeper").and_return(zookeeper)
      expect(LinuxAdmin::Service).to receive(:new).with("kafka").and_return(kafka)
      expect(LinuxAdmin::Service).to receive(:new).with("evmserverd").and_return(@evmserverd)
    end

    it "starts the needed services" do
      expect(@evmserverd).to receive(:running?).and_return(true)
      expect(@evmserverd).to receive(:restart)

      subject.send(:restart_services)
    end

    it "does not restart evmserverd if it is not running" do
      expect(@evmserverd).to receive(:running?).and_return(false)
      expect(@evmserverd).to_not receive(:restart)

      subject.send(:restart_services)
    end
  end
end
