describe ManageIQ::ApplianceConsole::InternalDatabaseConfiguration do
  before do
    @config = described_class.new
  end

  context ".new" do
    it "set defaults automatically" do
      expect(@config.host).to eq('localhost')
      expect(@config.username).to eq("root")
      expect(@config.database).to eq("vmdb_production")
      expect(@config.run_as_evm_server).to be true
    end
  end

  context "postgresql service" do
    it "#start_postgres (private)" do
      allow(LinuxAdmin::Service).to receive(:new).and_return(double(:service).as_null_object)
      allow(ManageIQ::ApplianceConsole::PostgresAdmin).to receive_messages(:service_name => 'postgresql')
      expect(@config).to receive(:block_until_postgres_accepts_connections)
      @config.send(:start_postgres)
    end
  end

  it "#choose_disk" do
    expect(@config).to receive(:ask_for_disk)
    @config.choose_disk
  end

  context "#check_disk_is_mount_point" do
    it "not raise error if disk is given" do
      expect(@config).to receive(:disk).and_return("/x")
      expect(@config).to receive(:mount_point).and_return("/x")
      @config.check_disk_is_mount_point
    end

    it "not raise error if no disk given but mount point for database is really a mount point" do
      expect(@config).to receive(:disk).and_return(nil)
      expect(@config).to receive(:mount_point).and_return("/x")
      expect(@config).to receive(:pg_mount_point?).and_return(true)
      @config.check_disk_is_mount_point
    end

    it "raise error if no disk given and not a mount point" do
      expect(@config).to receive(:disk).and_return(nil)
      expect(@config).to receive(:mount_point).and_return("/x")
      expect(@config).to receive(:pg_mount_point?).and_return(false)
      expect { @config.check_disk_is_mount_point }.to raise_error(RuntimeError, /Internal databases require a volume mounted at \/x/)
    end
  end

  it ".postgresql_template" do
    allow(ManageIQ::ApplianceConsole::PostgresAdmin).to receive_messages(:data_directory     => Pathname.new("/var/lib/pgsql/data"))
    allow(ManageIQ::ApplianceConsole::PostgresAdmin).to receive_messages(:template_directory => Pathname.new("/opt/manageiq/manageiq-appliance/TEMPLATE"))
    expect(described_class.postgresql_template.to_s).to end_with("TEMPLATE/var/lib/pgsql/data")
  end

  describe "#initialize_postgresql_disk" do
    before do
      lvm = double("LogicalVolumeManagement", :setup => nil)
      expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).to receive(:new).and_return(lvm)
    end

    it "resets the permissions on the postgres users home directory if we mount on top of it" do
      allow(@config).to receive(:mount_point).and_return(Pathname.new("/var/lib/pgsql"))
      expect(FileUtils).to receive(:chown).with(ManageIQ::ApplianceConsole::PostgresAdmin.user, ManageIQ::ApplianceConsole::PostgresAdmin.group, "/var/lib/pgsql")
      expect(FileUtils).to receive(:chmod).with(0o700, "/var/lib/pgsql")

      @config.initialize_postgresql_disk
    end

    it "leaves the mount point alone if it is not the postgres users home directory" do
      allow(@config).to receive(:mount_point).and_return(Pathname.new("/tmp/pgsql"))
      expect(FileUtils).not_to receive(:chown)
      expect(FileUtils).not_to receive(:chown)

      @config.initialize_postgresql_disk
    end
  end
end
