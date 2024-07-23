require 'tempfile'

describe ManageIQ::ApplianceConsole::MessageServerConfiguration do
  let(:message_keystore_username) { "admin" }
  let(:message_keystore_password) { "super_secret" }
  subject { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password) }
  let(:subject_ip) { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password, :message_server_host => "192.0.2.0") }
  let(:subject_persistent_disk) { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password, :message_server_host => "192.0.2.0", :message_persistent_disk => "/tmp/disk") }

  before do
    @spec_name = File.basename(__FILE__).split(".rb").first.freeze
    @tmp_base_dir = Pathname.new(Dir.mktmpdir)
    @tmp_miq_config_dir = Pathname.new(Dir.mktmpdir)
    @this = ManageIQ::ApplianceConsole::MessageConfiguration
    @this_server = ManageIQ::ApplianceConsole::MessageServerConfiguration
    @keystore_path = Pathname.new("#{@tmp_base_dir}/config/keystore/keystore.jks")
    stub_const("#{@this}::BASE_DIR", @tmp_base_dir)
    stub_const("#{@this}::LOGS_DIR", "#{@tmp_base_dir}/logs")
    stub_const("#{@this}::CONFIG_DIR", "#{@tmp_base_dir}/config")
    stub_const("#{@this}::SAMPLE_CONFIG_DIR", "#{@tmp_base_dir}/config-sample")
    stub_const("#{@this}::MIQ_CONFIG_DIR", "#{@tmp_base_dir}/config-sample")
    stub_const("#{@this_server}::PERSISTENT_DIRECTORY", "#{@tmp_base_dir}/kafka_persistent_data")

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
      allow(subject).to receive(:host_resolvable?).and_return(true)
      allow(subject).to receive(:host_reachable?).and_return(true)
      allow(subject).to receive(:message_server_configured?).and_return(false)
    end

    context "when not using a new persistent disk" do
      before do
        expect(subject).to receive(:use_new_disk).and_return(false)
      end

      it "should prompt for message_keystore_username and message_keystore_password" do
        expect(subject).to receive(:ask_for_messaging_hostname).with("Message Server Hostname", "my-host-name.example.com").and_return("my-host-name.example.com")
        expect(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
        expect(subject).to receive(:just_ask).with(/Message Keystore Password/i, anything).twice.and_return("top_secret")

        allow(subject).to receive(:say).at_least(5).times

        expect(subject.send(:ask_questions)).to be_truthy
      end

      it "should re-prompt when an empty message_keystore_password is given" do
        expect(subject).to receive(:ask_for_messaging_hostname).with("Message Server Hostname", "my-host-name.example.com").and_return("my-host-name.example.com")
        expect(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
        expect(subject).to receive(:just_ask).with(/Message Keystore Password/i, anything).and_return("")
        expect(subject).to receive(:just_ask).with(/Message Keystore Password/i, anything).twice.and_return("top_secret")
        expect(subject).to receive(:say).with("\nPassword can not be empty, please try again")

        allow(subject).to receive(:say).at_least(5).times

        expect(subject.send(:ask_questions)).to be_truthy
      end

      it "should display Server Hostname and Keystore Username" do
        allow(subject).to receive(:ask_for_messaging_hostname).with("Message Server Hostname", "my-host-name.example.com").and_return("my-host-name.example.com")
        allow(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
        expect(subject).to receive(:just_ask).with(/Message Keystore Password/i, anything).twice.and_return("top_secret")

        expect(subject).to receive(:say).with("\nMessage Server Parameters:\n\n")
        expect(subject).to receive(:say).with("\nMessage Server Configuration:\n")
        expect(subject).to receive(:say).with("Message Server Details:\n")
        expect(subject).to receive(:say).with("    Message Server Hostname: my-host-name.example.com\n")
        expect(subject).to receive(:say).with("  Message Keystore Username: admin\n")

        expect(subject.send(:ask_questions)).to be_truthy
      end
    end

    context "when using a new persistent disk" do
      before do
        expect(subject).to receive(:use_new_disk).and_return(true)
      end

      it "should prompt for message_keystore_username, message_keystore_password and persistent disk" do
        message_persistent_disk = LinuxAdmin::Disk.new(:path => "/tmp/disk")
        expect(subject).to receive(:ask_for_messaging_hostname).with("Message Server Hostname", "my-host-name.example.com").and_return("my-host-name.example.com")
        expect(subject).to receive(:ask_for_string).with("Message Keystore Username", message_keystore_username).and_return("admin")
        expect(subject).to receive(:just_ask).with(/Message Keystore Password/i, anything).twice.and_return("top_secret")
        expect(subject).to receive(:ask_for_disk).with("Persistent disk").and_return(message_persistent_disk)

        allow(subject).to receive(:say).at_least(5).times

        expect(subject.send(:ask_questions)).to be_truthy
      end
    end
  end

  describe "#configure_persistent_disk" do
    it "configure the new persistent disk" do
      expect(subject_persistent_disk).to receive(:say).with("Configure Persistent Disk")
      expect(subject_persistent_disk).to receive(:deactivate_services)
      expect(FileUtils).to receive(:chown).with("kafka", "kafka", @this_server::PERSISTENT_DIRECTORY)
      expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).to receive(:new).and_return(double(@spec_name, :setup => true))
      expect(subject_persistent_disk.send(:configure_persistent_disk)).to be_truthy
      expect(File.directory?(@this_server::PERSISTENT_DIRECTORY)).to be_truthy
    end

    it "if no persistent disk is specified it will not be configured" do
      expect(subject).not_to receive(:say)
      expect(subject).not_to receive(:deactivate_services)
      expect(FileUtils).not_to receive(:chown)
      expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).not_to receive(:new)
      expect(subject.send(:configure_persistent_disk)).to be_truthy
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
          .with("keytool", :params     => {"-keystore" => @keystore_path,
                                           "-validity" => 10_000,
                                           "-genkey"   => nil,
                                           "-keyalg"   => "RSA",
                                           "-alias"    => ks_alias,
                                           "-dname"    => "cn=#{ks_alias}",
                                           "-ext"      => ext},
                           :stdin_data => "#{message_keystore_password}\n#{message_keystore_password}\n\n")
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
        expect(subject.send(:create_server_properties)).to be_truthy
        expect(subject.server_properties_path).to exist
      end

      it "correctly populates the server properties config file" do
        expect(File).to receive(:write).with(subject.server_properties_path, content, :mode => "a")
        expect(subject.send(:create_server_properties)).to be_truthy
      end

      it "does not recreate the server properties config file if it already exists" do
        expect(subject).to receive(:say)
        File.write(subject.server_properties_path, content, :mode => "a")
        expect(File).not_to receive(:write)
        expect(subject.send(:create_server_properties)).to be_nil
      end
    end

    context "with hostname" do
      let(:ident_algorithm) { "HTTPS" }
      let(:client_auth) { "required" }
      let(:message_server_host) { "my-kafka-server.example.com" }
      include_examples "service properties file"
    end
  end

  describe "#configured?" do
    it "returns true if the kafka service is running" do
      kafka = LinuxAdmin::Service.new("kafka")
      expect(kafka).to receive(:running?).and_return(true)
      expect(LinuxAdmin::Service).to receive(:new).with("kafka").and_return(kafka)

      expect(described_class.configured?).to be_truthy
    end

    it "returns true if the zookeeper service is running even if kafka is not" do
      kafka = LinuxAdmin::Service.new("kafka")
      expect(kafka).to receive(:running?).and_return(false)

      zookeeper = LinuxAdmin::Service.new("zookeeper")
      expect(zookeeper).to receive(:running?).and_return(true)

      expect(LinuxAdmin::Service).to receive(:new).with("zookeeper").and_return(zookeeper)
      expect(LinuxAdmin::Service).to receive(:new).with("kafka").and_return(kafka)

      expect(described_class.configured?).to be_truthy
    end

    it "returns false if neither the zookeeper service or the kafka service are running" do
      kafka = LinuxAdmin::Service.new("kafka")
      expect(kafka).to receive(:running?).and_return(false)

      zookeeper = LinuxAdmin::Service.new("zookeeper")
      expect(zookeeper).to receive(:running?).and_return(false)

      expect(LinuxAdmin::Service).to receive(:new).with("zookeeper").and_return(zookeeper)
      expect(LinuxAdmin::Service).to receive(:new).with("kafka").and_return(kafka)

      expect(described_class.configured?).not_to be_truthy
    end
  end

  describe "#initialize" do
    context "when --message-server-host is not specified" do
      subject { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password) }

      it "sets message_server_host to my hostname" do
        hosts = LinuxAdmin::Hosts.new
        expect(hosts).to receive(:hostname).and_return("my-hostname")
        expect(LinuxAdmin::Hosts).to receive(:new).and_return(hosts)

        expect(subject.message_server_host).to eq("my-hostname")
      end
    end

    context "when --message-server-host is specified" do
      subject { described_class.new(:message_keystore_username => message_keystore_username, :message_keystore_password => message_keystore_password, :message_server_host => "192.0.2.1" ) }

      it "sets message_server_host to the provided value" do
        expect(subject.message_server_host).to eq("192.0.2.1")
      end
    end
  end
end
