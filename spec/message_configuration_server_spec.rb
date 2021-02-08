require 'tempfile'

describe ManageIQ::ApplianceConsole::MessageServerConfiguration do
  let(:username) { "admin" }
  let(:password) { "super_secret" }
  subject { described_class.new(:username => username, :password => password) }
  let(:subject_ip) { described_class.new(:username => username, :password => password, :server_host => "192.0.2.0") }

  before do
    @spec_name = File.basename(__FILE__).split(".rb").first.freeze
    @tmp_base_dir = Pathname.new(Dir.mktmpdir)
    @tmp_miq_config_dir = Pathname.new(Dir.mktmpdir)
    @this = ManageIQ::ApplianceConsole::MessageConfiguration
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

    it "should prompt for Username and Password" do
      expect(subject).to receive(:ask_for_string).with("Message Server Hostname or IP address", "my-host-name.example.com").and_return("my-host-name.example.com")
      expect(subject).to receive(:ask_for_string).with("Message Key Username", username).and_return("admin")
      expect(subject).to receive(:ask_for_password).with("Message Key Password").and_return("top_secret")

      allow(subject).to receive(:say).at_least(5).times

      expect(subject.send(:ask_questions)).to be_truthy
    end

    it "should display Server Hostname and Key Username" do
      allow(subject).to receive(:ask_for_string).with("Message Server Hostname or IP address", "my-host-name.example.com").and_return("my-host-name.example.com")
      allow(subject).to receive(:ask_for_string).with("Message Key Username", username).and_return("admin")
      allow(subject).to receive(:ask_for_password).with("Message Key Password").and_return("top_secret")

      expect(subject).to receive(:say).with("\nMessage Server Parameters:\n\n")
      expect(subject).to receive(:say).with("\nMessage Server Configuration:\n")
      expect(subject).to receive(:say).with("Message Server Details:\n")
      expect(subject).to receive(:say).with("  Message Server Hostname:   my-host-name.example.com\n")
      expect(subject).to receive(:say).with("  Message Key Username:      admin\n")

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
          username=#{username}
          password=#{password}
          user_admin=#{password} ;
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
      expect(AwesomeSpawn).to receive(:run!).with("firewall-cmd --add-port=9093/tcp --permanent")
      expect(AwesomeSpawn).to receive(:run!).with("firewall-cmd --reload")
      expect(subject.send(:configure_firewall)).to be_nil
    end
  end

  describe "#configure_keystore" do
    context "with IP address" do
      before do
        expect(subject_ip).to receive(:say).with("Configure Keystore")
      end

      it "creates and populates the keystore directory" do
        allow(AwesomeSpawn).to receive(:run!).exactly(7).times

        expect(AwesomeSpawn).to receive(:run!).with("keytool", :params => {"-keystore" => "#{@tmp_base_dir}/config/keystore/keystore.jks" , "-alias" => "localhost", "-validity" => 10_000, "-genkey" => nil, "-keyalg" => "RSA", "-storepass" => password, "-keypass" => password, "-dname" => "cn=localhost", "-ext" => "san=ip:192.0.2.0"})
        expect(subject_ip.send(:configure_keystore)).to be_nil
        expect(File.directory?(subject_ip.keystore_dir_path)).to be_truthy
      end
    end

    context "with DNS hostname" do
      before do
        expect(subject).to receive(:say).with("Configure Keystore")
      end

      it "creates and populates the keystore directory" do
        allow(AwesomeSpawn).to receive(:run!).exactly(7).times

        expect(AwesomeSpawn).to receive(:run!).with("keytool", :params => {"-keystore" => "#{@tmp_base_dir}/config/keystore/keystore.jks" , "-alias" => "my-host-name.example.com", "-validity" => 10_000, "-genkey" => nil, "-keyalg" => "RSA", "-storepass" => password, "-keypass" => password, "-dname" => "cn=my-host-name.example.com", "-ext" => "san=dns:my-host-name.example.com"})
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
  end

  describe "#create_server_properties" do
    context "with IP address" do
      before do
        @ident_algorithm = ""
        @client_auth = "none"

        @content = <<~SERVER_PROPERTIES

          listeners=SASL_SSL://:9093

          ssl.endpoint.identification.algorithm=#{@ident_algorithm}
          ssl.keystore.location=#{subject.keystore_path}
          ssl.keystore.password=#{password}
          ssl.key.password=#{password}

          ssl.truststore.location=#{subject.truststore_path}
          ssl.truststore.password=#{password}

          ssl.client.auth=#{@client_auth}

          sasl.enabled.mechanisms=PLAIN
          sasl.mechanism.inter.broker.protocol=PLAIN

          security.inter.broker.protocol=SASL_SSL
        SERVER_PROPERTIES

        FileUtils.touch(subject_ip.server_properties_sample_path)
        FileUtils.touch(subject_ip.server_properties_path)

        expect(subject_ip).to receive(:say).with("Create Server Properties")
      end

      it "creates the service properties config file" do
        expect(subject_ip.send(:create_server_properties)).to be_positive
        expect(subject_ip.server_properties_path).to exist
      end

      it "correctly populates the server properties config file" do
        expect(File).to receive(:write).with(subject_ip.server_properties_path, @content, :mode => "a")
        expect(subject_ip.send(:create_server_properties)).to be_nil
      end

      it "does not recreate the server properties config file if it already exists" do
        expect(subject_ip).to receive(:say)
        File.write(subject_ip.server_properties_path, @content, :mode => "a")
        expect(File).not_to receive(:write)
        expect(subject_ip.send(:create_server_properties)).to be_nil
      end
    end

    context "with DNS hostname" do
      before do
        @ident_algorithm = "HTTPS"
        @client_auth = "required"

        @content = <<~SERVER_PROPERTIES

          listeners=SASL_SSL://:9093

          ssl.endpoint.identification.algorithm=#{@ident_algorithm}
          ssl.keystore.location=#{subject.keystore_path}
          ssl.keystore.password=#{password}
          ssl.key.password=#{password}

          ssl.truststore.location=#{subject.truststore_path}
          ssl.truststore.password=#{password}

          ssl.client.auth=#{@client_auth}

          sasl.enabled.mechanisms=PLAIN
          sasl.mechanism.inter.broker.protocol=PLAIN

          security.inter.broker.protocol=SASL_SSL
        SERVER_PROPERTIES

        FileUtils.touch(subject.server_properties_sample_path)
        FileUtils.touch(subject.server_properties_path)

        expect(subject).to receive(:say).with("Create Server Properties")
      end


      it "creates the service properties config file" do
        expect(subject.send(:create_server_properties)).to be_positive
        expect(subject.server_properties_path).to exist
      end

      it "correctly populates the server properties config file" do
        expect(File).to receive(:write).with(subject.server_properties_path, @content, :mode => "a")
        expect(subject.send(:create_server_properties)).to be_nil
      end

      it "does not recreate the server properties config file if it already exists" do
        expect(subject).to receive(:say)
        File.write(subject.server_properties_path, @content, :mode => "a")
        expect(File).not_to receive(:write)
        expect(subject.send(:create_server_properties)).to be_nil
      end
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
          hostname: my-host-name.example.com
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

  describe "#post_activation" do
    it "starts the needed services" do
      expect(subject).to receive(:say).exactly(3).times

      evmserverd = LinuxAdmin::Service.new("evmserverd")
      expect(evmserverd).to receive(:running?).and_return(true)
      expect(evmserverd).to receive(:restart)

      zookeeper = LinuxAdmin::Service.new("zookeeper")
      expect(zookeeper).to receive(:start).and_return(zookeeper)
      expect(zookeeper).to receive(:enable)

      kafka = LinuxAdmin::Service.new("kafka")
      expect(kafka).to receive(:start).and_return(kafka)
      expect(kafka).to receive(:enable)

      expect(LinuxAdmin::Service).to receive(:new).with("zookeeper").and_return(zookeeper)
      expect(LinuxAdmin::Service).to receive(:new).with("kafka").and_return(kafka)
      expect(LinuxAdmin::Service).to receive(:new).with("evmserverd").and_return(evmserverd)

      expect(subject.send(:post_activation)).to be_nil
    end

    it "does not restart evmserverd if it is not running" do
      expect(subject).to receive(:say).exactly(3).times

      evmserverd = LinuxAdmin::Service.new("evmserverd")
      expect(evmserverd).to receive(:running?).and_return(false)
      expect(evmserverd).to_not receive(:restart)

      zookeeper = LinuxAdmin::Service.new("zookeeper")
      expect(zookeeper).to receive(:start).and_return(zookeeper)
      expect(zookeeper).to receive(:enable)

      kafka = LinuxAdmin::Service.new("kafka")
      expect(kafka).to receive(:start).and_return(kafka)
      expect(kafka).to receive(:enable)

      expect(LinuxAdmin::Service).to receive(:new).with("zookeeper").and_return(zookeeper)
      expect(LinuxAdmin::Service).to receive(:new).with("kafka").and_return(kafka)
      expect(LinuxAdmin::Service).to receive(:new).with("evmserverd").and_return(evmserverd)
      expect(subject.send(:post_activation)).to be_nil
    end
  end
end
