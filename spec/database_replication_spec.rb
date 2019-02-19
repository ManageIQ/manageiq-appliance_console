describe ManageIQ::ApplianceConsole::DatabaseReplication do
  SPEC_NAME = File.basename(__FILE__).split(".rb").first.freeze

  before do
    allow(subject).to receive(:say)
    allow(subject).to receive(:clear_screen)
    allow(subject).to receive(:agree)
    allow(subject).to receive(:ask_for_ip_or_hostname)
    allow(subject).to receive(:ask_for_password)
  end

  context "#ask_for_unique_cluster_node_number" do
    it "should ask for a unique number" do
      expect(subject).to receive(:ask_for_integer).with(/uniquely identifying this node/i).and_return(1)
      subject.ask_for_unique_cluster_node_number
      expect(subject.node_number).to eq(1)
    end
  end

  context "#ask_for_database_credentials" do
    before do
      subject.database_name     = "defaultdatabasename"
      subject.database_user     = "defaultuser"
      subject.database_password = nil
      subject.primary_host      = "defaultprimary"
    end

    it "should store the newly supplied values" do
      expect(subject).to receive(:just_ask).with(/ name/i, "defaultdatabasename").and_return("newdatabasename")
      expect(subject).to receive(:just_ask).with(/ user/i, "defaultuser").and_return("newuser")
      expect(subject).to receive(:ask_for_password).with(/password/i, any_args).twice.and_return("newpassword")
      expect(subject)
        .to receive(:ask_for_ip_or_hostname).with(/primary.*hostname/i, "defaultprimary").and_return("newprimary")

      subject.ask_for_database_credentials

      expect(subject.database_name).to eq("newdatabasename")
      expect(subject.database_user).to eq("newuser")
      expect(subject.database_password).to eq("newpassword")
      expect(subject.primary_host).to eq("newprimary")
    end
  end

  context "#confirm_reconfiguration" do
    it "should log a warning and ask to continue anyway" do
      expect(subject).to receive(:say).with(/^warning/i)
      expect(subject).to receive(:agree).with(/^continue/i)

      subject.confirm_reconfiguration
    end
  end

  context "#create_config_file" do
    it "writes the config file contents" do
      expect(subject).to receive(:config_file_contents).and_return("the contents")
      expect(File).to receive(:write).with(described_class::REPMGR_CONFIG, "the contents")
      expect(subject.create_config_file("host")).to be true
    end
  end

  context "#config_file_contents" do
    let(:expected_config_file) do
      <<-EOS.strip_heredoc
        node_id=nodenumber
        node_name=host
        conninfo='host=host user=user dbname=databasename'
        use_replication_slots=1
        pg_basebackup_options='--wal-method=stream'
        failover=automatic
        promote_command='repmgr standby promote -f /etc/repmgr/10/repmgr.conf --log-to-file'
        follow_command='repmgr standby follow -f /etc/repmgr/10/repmgr.conf --log-to-file --upstream-node-id=%n'
        log_file=/var/log/repmgr/repmgrd.log
        service_start_command='sudo systemctl start postgresql-9.5'
        service_stop_command='sudo systemctl stop postgresql-9.5'
        service_restart_command='sudo systemctl restart postgresql-9.5'
        service_reload_command='sudo systemctl reload postgresql-9.5'
        data_directory='/var/lib/pgsql'
      EOS
    end

    before do
      ENV["APPLIANCE_PG_DATA"] = "/var/lib/pgsql"
      ENV["APPLIANCE_PG_SERVICE"] = "postgresql-9.5"
    end

    after do
      ENV.delete("APPLIANCE_PG_DATA")
      ENV.delete("APPLIANCE_PG_SERVICE")
    end

    it "returns the correct contents" do
      subject.node_number       = "nodenumber"
      subject.database_name     = "databasename"
      subject.database_user     = "user"

      expect(subject.config_file_contents("host")).to eq(expected_config_file)
    end
  end

  context "#write_pgpass_file" do
    before do
      @tempfile_pgpass = Tempfile.new("pgpass")
      @pgpass_path = @tempfile_pgpass.path
      stub_const("#{described_class}::PGPASS_FILE", @pgpass_path)
    end

    after do
      @tempfile_pgpass.close!
    end

    it "writes the .pgpass file correctly" do
      subject.database_name     = "dbname"
      subject.database_user     = "someuser"
      subject.database_password = "secret"

      expect(FileUtils).to receive(:chown).with("postgres", "postgres", @pgpass_path)
      subject.write_pgpass_file

      expect(File.read(@pgpass_path)).to eq(<<-EOS.gsub(/^\s+/, ""))
        *:*:dbname:someuser:secret
        *:*:replication:someuser:secret
      EOS

      pgpass_stat = File.stat(@pgpass_path)
      expect(pgpass_stat.mode.to_s(8)).to eq("100600")
    end
  end
end
