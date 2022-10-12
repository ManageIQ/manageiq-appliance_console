describe ManageIQ::ApplianceConsole::DatabaseConfiguration do
  before do
    @config = described_class.new
  end

  context ".initialize" do
    it "accepts hash attributes" do
      config = described_class.new(:adapter => "test", :port => 5433)
      expect(config.adapter).to eq("test")
      expect(config.port).to eq(5433)
    end

    it "default attributes" do
      config = described_class.new
      expect(config.adapter).to eq("postgresql")
      expect(config.port).to be_nil
    end

    it "interactive => false" do
      config = described_class.new(:interactive => false)
      expect(config).not_to be_interactive
    end

    it "interactive defaults to true" do
      config = described_class.new
      expect(config).to be_interactive
    end

    it "raises ArgumentError on unknown attributes" do
      expect { described_class.new(:unknown => "test") }.to raise_error(ArgumentError)
    end
  end

  context "#friendly_inspect" do
    it "normal case" do
      config = described_class.new(:host => "abc", :username => "abc", :database => "abc", :region => 1)
      expect(config.friendly_inspect).to eq("Host:     abc\nUsername: abc\nDatabase: abc\nRegion:   1\n")
    end

    it "without region" do
      config = described_class.new(:host => "abc", :username => "abc", :database => "abc")
      expect(config.friendly_inspect).to eq("Host:     abc\nUsername: abc\nDatabase: abc\n")
    end
  end

  context "#password=" do
    it "decrypts encrypted value" do
      @config.password = ManageIQ::Password.encrypt("test")
      expect(@config.password).to eq("test")
    end

    it "clear text" do
      @config.password = "test"
      expect(@config.password).to eq("test")
    end
  end

  context ".encrypt_password" do
    it "normal case" do
      hash = {"production" => {"password" => "test"}}
      settings = described_class.encrypt_password(hash)
      expect(settings["production"]["password"]).to be_encrypted("test")
    end

    it "encrypts once" do
      hash = {"production" => {"password" => "v2:{DUb5th63TM+zIB6RhnTtVg==}"}}
      expect(described_class.encrypt_password(hash)["production"]["password"]).to eq("v2:{DUb5th63TM+zIB6RhnTtVg==}")
    end

    it "doesn't modify the receiver" do
      hash = {"production" => {"password" => "test"}}
      described_class.encrypt_password(hash)
      expect(hash["production"]["password"]).to eq("test")
    end

    it "retains other environments" do
      hash = {"production" => {"password" => "test"}, "development" => {"password" => "test2"}}
      settings = described_class.encrypt_password(hash)
      expect(settings["development"]["password"]).to eq("test2")
    end
  end

  context ".decrypt_password" do
    it "decrypt" do
      hash = {"production" => {"password" => ManageIQ::Password.encrypt("test")}}
      expect(described_class.decrypt_password(hash)["production"]["password"]).to eq("test")
    end

    it "shouldn't introduce password field if not present" do
      hash = {"production" => {}}
      expect(described_class.decrypt_password(hash)["production"]).not_to have_key("password")
    end
  end

  context "#validated" do
    it "normal case" do
      allow(@config).to receive_messages(:validate! => "truthy_object")
      expect(@config.validated).to be_truthy
    end

    it "failure" do
      expected_message = "FATAL: database 'bad_db' does not exist"
      allow(@config).to receive(:validate!).and_raise(expected_message)
      expect(@config).to receive(:say_error).with(:validated, expected_message)
      expect(@config.validated).to be_falsey
    end
  end

  context "#create_region" do
    before do
      @config.region = 42
      expect(ManageIQ::ApplianceConsole::Utilities).to receive(:bail_if_db_connections)
    end

    it "normal case" do
      expect(@config).not_to receive(:log_and_feedback_exception)
      stub_good_run("rake evm:db:region", :chdir => ManageIQ::ApplianceConsole::RAILS_ROOT, :env => {"REGION" => "42", "VERBOSE" => "false"}, :params => {})
      expect(@config.create_region).to be_truthy
    end

    it "failure" do
      expect(@config).not_to receive(:log_and_feedback_exception)
      stub_bad_run("rake evm:db:region", :chdir => ManageIQ::ApplianceConsole::RAILS_ROOT, :env => {"REGION" => "42", "VERBOSE" => "false"}, :params => {})
      expect(@config.create_region).to be_falsey
    end
  end

  context "#ask_for_database_credentials" do
    subject do
      # Note: this will move from External to DatabaseConfiguration
      stubbed_say(ManageIQ::ApplianceConsole::ExternalDatabaseConfiguration)
    end

    it "should default prompts based upon previous values (no default password)" do
      subject.host     = "defaulthost"
      subject.database = "defaultdb"
      subject.username = "defaultuser"
      subject.password = nil

      expect(subject).to receive(:just_ask).with(/hostname/i, "defaulthost", anything, anything).and_return("newhost")
      expect(subject).to receive(:just_ask).with(/port/i, 5432, anything, anything, anything).and_return(5432)
      expect(subject).to receive(:just_ask).with(/the database/i, "defaultdb").and_return("x")
      expect(subject).to receive(:just_ask).with(/user/i, "defaultuser").and_return("x")
      expect(subject).to receive(:just_ask).with(/password/i, nil).twice.and_return("x")

      subject.ask_for_database_credentials
    end

    it "should default password prompt with stars (choosing default doesnt confirm password)" do
      subject.password = "defaultpass"

      expect(subject).to receive(:just_ask).with(/hostname/i, anything, anything, anything).and_return("x")
      expect(subject).to receive(:just_ask).with(/port/i, anything, anything, anything, anything).and_return(5432)
      expect(subject).to receive(:just_ask).with(/the database/i, anything).and_return("x")
      expect(subject).to receive(:just_ask).with(/user/i,     anything).and_return("x")
      expect(subject).to receive(:just_ask).with(/password/i, "********").and_return("********")

      subject.ask_for_database_credentials
    end

    it "should ask for user/password (with confirm) if not local" do
      expect(subject).to receive(:just_ask).with(/hostname/i, anything, anything, anything).and_return("host")
      expect(subject).to receive(:just_ask).with(/port/i, anything, anything, anything, anything).and_return(5432)
      expect(subject).to receive(:just_ask).with(/the database/i, anything).and_return("x")
      expect(subject).to receive(:just_ask).with(/user/i,     anything).and_return("x")
      expect(subject).to receive(:just_ask).with(/password/i, anything).twice.and_return("the password")

      subject.ask_for_database_credentials
    end

    it "should only ask for password (with confirm) if local" do
      expect(subject).to receive(:just_ask).with(/hostname/i, anything, anything, anything).and_return("localhost")
      expect(subject).to receive(:just_ask).with(/password/i, anything).twice.and_return("the password")

      subject.ask_for_database_credentials
    end
  end

  context "#ask_for_database_credentials (internal)" do
    subject do
      Class.new(ManageIQ::ApplianceConsole::InternalDatabaseConfiguration) do
        include ManageIQ::ApplianceConsole::Prompts
        # global variable
        def say(*_args)
        end
      end.new
      stubbed_say(ManageIQ::ApplianceConsole::InternalDatabaseConfiguration)
    end

    it "should ask for password (with confirm) if local" do
      expect(subject).to receive(:just_ask).with(/password/i, anything).twice.and_return("the password")

      subject.ask_for_database_credentials
    end

    it "should prompt again if passwords do not match" do
      expect(subject).to receive(:just_ask).with(/password/i, anything).twice.and_return(*%w(pass1 pass2 pass3 pass3))

      subject.ask_for_database_credentials
      expect(subject.password).to eq("pass3")
    end

    it "should raise an error if passwords do not match twice" do
      expect(subject).to receive(:just_ask).with(/password/i, anything).twice.and_return(*%w(pass1 pass2 pass3 pass4))

      expect { subject.ask_for_database_credentials }.to raise_error(RuntimeError, "passwords did not match")
    end

    it "does not allow empty password" do
      expect(subject).to receive(:just_ask).and_return(" ")
      expect(subject).to receive(:say).with("\nPassword can not be empty, please try again")
      expect(subject).to receive(:loop).and_yield
      subject.ask_for_database_credentials
    end

    it "ask for password only once when password_twice is false" do
      expect(subject).to receive(:just_ask).with(/password/i, anything).and_return("pass1")
      subject.ask_for_database_credentials(false)
      expect(subject.password).to eq("pass1")
    end
  end

  context "#create_or_join_region" do
    it "creates if region" do
      @config.region = 1
      expect(@config).to receive(:create_region)
      @config.create_or_join_region
    end

    it "joins without a region" do
      expect(@config).to receive(:join_region)
      @config.create_or_join_region
    end
  end

  it "#say_error" do
    error = "NoMethodError: undefined method `[]' for NilClass"
    expected_message = "Create region failed with error - #{error}."
    expect(@config).to receive(:say) do |message|
       expect(message).to include(expected_message)
    end
    @config.interactive = true
    expect(@config).to receive(:press_any_key)
    expect { @config.say_error(:create_region, error) }.to raise_error(ManageIQ::ApplianceConsole::MiqSignalError)
  end

  it "#say_error interactive=> false" do
    config = described_class.new(:interactive => false)
    expect(config).to receive(:say)
    expect(config).to_not receive(:press_any_key)
    expect { config.say_error(:create_region, "Error message") }.to raise_error(ManageIQ::ApplianceConsole::MiqSignalError)
  end

  context "#log_and_feedback" do
    before do
      @old_logger = @config.logger
    end

    after do
      @config.logger = @old_logger
    end

    it "raises ArgumentError with no block_given" do
      @config.logger = nil
      expect { @config.log_and_feedback(:some_method) }.to raise_error(ArgumentError)
    end

    it "normal case" do
      expected_logging = double
      expect(expected_logging).to receive(:info).twice
      @config.logger = expected_logging
      expect(@config).to receive(:say_info).with(:some_method, "starting")
      expect(@config).to receive(:say_info).with(:some_method, "complete")
      expect(@config.log_and_feedback(:some_method) { :result }).to eq(:result)
    end

    context "raising exception:" do
      before do
        expected_logging = double
        expect(expected_logging).to receive(:info).once
        @config.logger = expected_logging
        @backtrace = [
          "gems/linux_admin-0.4.0/lib/linux_admin/common.rb:40:in `run!'",
          "gems/linux_admin-0.4.0/lib/linux_admin/disk.rb:127:in `create_partition_table'",
          "appliance_console/database_configuration_spec.rb:192:in `block (4 levels) in <top (required)>'"
        ]
      end

      it "CommandResultError" do
        result    = double(:error => "stderr", :output => "stdout", :exit_status => 1)
        message   = "some error"
        exception = AwesomeSpawn::CommandResultError.new(message, result)
        exception.set_backtrace(@backtrace)

        expect(@config).to receive(:say_info).with(:some_method, "starting")
        expect(@config).to receive(:say_error).with(:some_method, exception.message)
        expect(@config).to receive(:log_error).with(:some_method, "Command failed: #{exception.message}. Error: stderr. Output: stdout. At: #{@backtrace.last}")
        expect(@config.log_and_feedback(:some_method) { raise exception }).to be_nil
      end

      it "ArgumentError" do
        message   = "some error"
        exception = ArgumentError.new(message)
        exception.set_backtrace(@backtrace)

        expect(@config).to receive(:say_info).with(:some_method, "starting")
        debugging = "Error: ArgumentError with message: #{message}"
        expect(@config).to receive(:say_error).with(:some_method, debugging)
        expect(@config).to receive(:log_error).with(:some_method, "#{debugging}. Failed at: #{@backtrace.first}")
        expect(@config.log_and_feedback(:some_method) { raise exception }).to be_nil
      end
    end
  end

  context "settings" do
    before do
      @settings = {
        "production" => {
          "adapter"  => "postgresql",
          "encoding" => "utf8",
          "host"     => "192.168.1.111",
          "username" => "original_username",
          "password" => "v2:{DUb5th63TM+zIB6RhnTtVg==}",
          "pools"    => "5",
        }
      }
      allow(described_class).to receive_messages(:load_current => @settings)
    end

    context "#merged_settings" do
      subject { @config.merged_settings["production"] }

      it "should inherit unchanged non-core values" do
        expect(subject).to include("encoding" => "utf8", "pools" => "5")
      end

      it "should override inherited values" do
        @config.host = "192.168.100.100"
        expect(subject).to include("host" => "192.168.100.100")
      end
    end

    context "#activate" do
      it "normal case" do
        allow(@config).to receive_messages(:validated => true)
        expect(@config).to receive(:create_or_join_region).and_return(true)
        expect(ManageIQ::ApplianceConsole::Utilities).to receive(:rake).with("evm:validate_encryption_key", {}).and_return(true)

        allow(@config).to receive_messages(:merged_settings => @settings)
        expect(@config).to receive(:do_save).with(@settings)
        expect(@config.activate).to be_truthy
      end

      it "doesn't save invalid settings" do
        allow(@config).to receive_messages(:validated => false)
        expect(@config).to receive(:do_save).never
        expect(@config.activate).to be_falsey
      end

      context "reverts on region failure" do
        before do
          allow(@config).to receive_messages(:validated => true)
          allow(@config).to receive_messages(:create_or_join_region => false)

          new_settings = {"production" => @settings["production"].dup}
          new_settings["production"]["host"] = "new_host"
          allow(@config).to receive_messages(:merged_settings => new_settings)
          expect(@config).to receive(:do_save).with("production" => hash_including(new_settings["production"].except("password")))
          expect(@config).to receive(:do_save).with("production" => hash_including(@settings["production"].except("password")))
        end

        it "where no exception is raised" do
          expect(@config.activate).to be_falsey
        end

        it "where an exception is raised" do
          allow(@config).to receive(:create_or_join_region).and_raise
          expect(@config.activate).to be_falsey
        end

        it "where the encryption key is invalid" do
          allow(ManageIQ::ApplianceConsole::Utilities).to receive(:rake).with("evm:validate_encryption_key", {}).and_return(false)
          expect(@config.activate).to be_falsey
        end
      end
    end

    describe "#start_evm" do
      it "forks and detaches the service start command" do
        expect(@config).to receive(:fork) do |&block|
          service = double(:service)
          expect(ManageIQ::ApplianceConsole::EvmServer).to receive(:start).with(:enable => true).and_return(service)
          block.call
          1234 # return a test pid
        end
        expect(Process).to receive(:detach).with(1234)
        @config.start_evm
      end
    end
  end

  context "with test database yml file" do
    let(:db_yml)   { Tempfile.new("appliance_console_database.yml") }
    let(:key_file) { Tempfile.new("encryption_key") }

    around(:each) do |example|
      db_yml.write(<<-DBYML)
---
production:
  database: prod_database
env1:
  database: database1
  username: user1
  host: host1.example.com
env2:
  database: database2
  username: user2
DBYML
      db_yml.close
      key_file.write("encryption_key")
      key_file.close
      begin
        example.run
      ensure
        db_yml.unlink
        key_file.unlink
      end
    end

    before do
      stub_const("#{described_class}::DB_YML", db_yml.path)
      stub_const("ManageIQ::ApplianceConsole::KEY_FILE", key_file.path)
    end

    describe ".database_host" do
      it "returns the proper host when host is specified" do
        allow(described_class).to receive(:rails_env).and_return('env1')
        expect(described_class.database_host).to eq("host1.example.com")
      end

      it "returns localhost when the host is not specified" do
        allow(described_class).to receive(:rails_env).and_return('env2')
        expect(described_class.database_host).to eq("localhost")
      end
    end

    describe ".database_name" do
      it "returns the correct database name" do
        allow(described_class).to receive(:rails_env).and_return('env1')
        expect(described_class.database_name).to eq("database1")
      end
    end
  end

  context "with no database yml file" do
    before do
      expect(described_class).to receive(:database_yml_configured?).and_return false
    end

    describe ".database_host" do
      it "returns nil" do
        expect(described_class.database_host).to be_nil
      end
    end

    describe ".database_name" do
      it "returns nil" do
        expect(described_class.database_name).to be_nil
      end
    end

    describe ".region" do
      it "returns nil" do
        expect(described_class.region).to be_nil
      end
    end
  end

  def stubbed_say(klass)
    Class.new(klass) do
      include ManageIQ::ApplianceConsole::Prompts
      # don't display the messages prompted to the end user
      def say(*_args)
      end
    end.new
  end
end
