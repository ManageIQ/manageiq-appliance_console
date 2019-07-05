describe ManageIQ::ApplianceConsole::LogicalVolumeManagement do
  before do
    @spec_name = File.basename(__FILE__).split(".rb").first
    @disk_double = double(@spec_name, :path => "/dev/vtest")
    @config = described_class.new(:disk => @disk_double, :mount_point => "/mount_point", :name => "test")
  end

  describe ".new" do
    it "ensures required disk option is provided" do
      expect { described_class.new(:mount_point => "/mount_point", :name => "test") }.to raise_error(ArgumentError)
    end

    it "ensures required mount_point option is provided" do
      expect { described_class.new(:disk => @disk_double, :name => "test") }.to raise_error(ArgumentError)
    end

    it "ensures required name option is provided" do
      expect do
        described_class.new(:disk => @disk_double, :mount_point => "/mount_point")
      end.to raise_error(ArgumentError)
    end

    it "sets derived and default instance variables automatically" do
      expect(@config.volume_group_name).to eq("vg_test")
      expect(@config.filesystem_type).to eq("xfs")
      expect(@config.logical_volume_path).to eq("/dev/vg_test/lv_test")
    end
  end

  describe "#setup" do
    before do
      expect(@disk_double).to receive(:partitions).and_return([:fake_partition])
      @config.disk = @disk_double

      @fstab = double(@spec_name)
      allow(@fstab).to receive_messages(:entries => [])
      allow(LinuxAdmin::FSTab).to receive_messages(:instance => @fstab)

      expect(AwesomeSpawn).to receive(:run!).with("parted -s /dev/vtest mkpart primary 0% 100%")
      expect(AwesomeSpawn).to receive(:run!).with("mkfs.#{@config.filesystem_type} /dev/vg_test/lv_test")
      expect(LinuxAdmin::Disk).to receive(:local).and_return([@disk_double])
      expect(LinuxAdmin::PhysicalVolume).to receive(:create).and_return(:fake_physical_volume)
      expect(LinuxAdmin::VolumeGroup).to receive(:create).and_return(:fake_volume_group)
      expect(FileUtils).to_not receive(:rm_rf).with(@config.mount_point)

      @fake_logical_volume = double(@spec_name, :path => "/dev/vg_test/lv_test")
      expect(LinuxAdmin::LogicalVolume).to receive(:create).and_return(@fake_logical_volume)
      @dos_disk_size = 2.terabyte - 1
      @gpt_disk_size = 2.terabyte
    end

    after do
      FileUtils.rm_f(@tmp_mount_point)
      FileUtils.rm_f(@config.mount_point)
    end

    it "sets up the logical disk when mount point is not a symbolic link" do
      expect(@disk_double).to receive(:size).and_return(@dos_disk_size)
      expect(@disk_double).to receive(:create_partition_table).with("msdos")
      @tmp_mount_point = @config.mount_point = Pathname.new(Dir.mktmpdir)
      expect(@fstab).to receive(:write!)
      expect(FileUtils).to_not receive(:mkdir_p).with(@config.mount_point)
      expect(AwesomeSpawn).to receive(:run!).with("mount", :params => ["-a"])

      @config.setup
      expect(@config.partition).to eq(:fake_partition)
      expect(@config.physical_volume).to eq(:fake_physical_volume)
      expect(@config.volume_group).to eq(:fake_volume_group)
      expect(@config.logical_volume).to eq(@fake_logical_volume)
      expect(@fstab.entries.count).to eq(1)
    end

    it "recreates the new mount point and sets up the logical disk when mount point is a symbolic link" do
      expect(@disk_double).to receive(:size).and_return(@dos_disk_size)
      expect(@disk_double).to receive(:create_partition_table).with("msdos")
      @tmp_mount_point = Pathname.new(Dir.mktmpdir)
      @config.mount_point = Pathname.new("#{Dir.tmpdir}/#{@spec_name}")
      FileUtils.ln_s(@tmp_mount_point, @config.mount_point)
      expect(@fstab).to receive(:write!)

      expect(FileUtils).to receive(:rm_rf).with(@config.mount_point)
      expect(FileUtils).to receive(:mkdir_p).with(@config.mount_point)
      expect(FileUtils).to_not receive(:mkdir_p).with(@config.mount_point)
      expect(AwesomeSpawn).to receive(:run!).with("mount", :params => ["-a"])
      @config.setup
      expect(@config.partition).to eq(:fake_partition)
      expect(@config.physical_volume).to eq(:fake_physical_volume)
      expect(@config.volume_group).to eq(:fake_volume_group)
      expect(@config.logical_volume).to eq(@fake_logical_volume)
      expect(@fstab.entries.count).to eq(1)
    end

    it "uses gpt partition table when disk size is over 2TB" do
      expect(@disk_double).to receive(:size).and_return(@gpt_disk_size)
      expect(@disk_double).to receive(:create_partition_table).with("gpt")
      @tmp_mount_point = @config.mount_point = Pathname.new(Dir.mktmpdir)
      expect(@fstab).to receive(:write!)
      expect(FileUtils).to_not receive(:mkdir_p).with(@config.mount_point)
      expect(AwesomeSpawn).to receive(:run!).with("mount", :params => ["-a"])

      @config.setup
      expect(@config.partition).to eq(:fake_partition)
      expect(@config.physical_volume).to eq(:fake_physical_volume)
      expect(@config.volume_group).to eq(:fake_volume_group)
      expect(@config.logical_volume).to eq(@fake_logical_volume)
      expect(@fstab.entries.count).to eq(1)
    end
  end

  describe "#update_fstab" do
    let(:fstab) do
      <<~END_OF_FSTAB

        #
        # /etc/fstab
        # Created by anaconda on Wed May 29 12:37:40 2019
        #
        # Accessible filesystems, by reference, are maintained under '/dev/disk'
        # See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info
        #
        /dev/mapper/VG--MIQ-lv_os /                       xfs     defaults        0 0
        UUID=02bf07b5-2404-4779-b93c-d8eb7f2eedea /boot                   xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_home /home                   xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_tmp /tmp                    xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_var /var                    xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_var_log /var/log                xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_var_log_audit /var/log/audit          xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_log /var/www/miq/vmdb/log   xfs     defaults        0 0
        /dev/mapper/VG--MIQ-lv_swap swap                    swap    defaults        0 0
      END_OF_FSTAB
    end

    before do
      stub_const("LinuxAdmin::FSTab", LinuxAdmin::FSTab.dup)
      expect(File).to receive(:read).with("/etc/fstab").and_return(fstab)
    end

    it "writes new entries" do
      new_content = <<~END_OF_FSTAB

        # /etc/fstab
        # Created by anaconda on Wed May 29 12:37:40 2019

        # Accessible filesystems, by reference, are maintained under '/dev/disk'
        # See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info

                        /dev/mapper/VG--MIQ-lv_os                     /  xfs   defaults 0 0
        UUID=02bf07b5-2404-4779-b93c-d8eb7f2eedea                 /boot  xfs   defaults 0 0
                      /dev/mapper/VG--MIQ-lv_home                 /home  xfs   defaults 0 0
                       /dev/mapper/VG--MIQ-lv_tmp                  /tmp  xfs   defaults 0 0
                       /dev/mapper/VG--MIQ-lv_var                  /var  xfs   defaults 0 0
                   /dev/mapper/VG--MIQ-lv_var_log              /var/log  xfs   defaults 0 0
             /dev/mapper/VG--MIQ-lv_var_log_audit        /var/log/audit  xfs   defaults 0 0
                       /dev/mapper/VG--MIQ-lv_log /var/www/miq/vmdb/log  xfs   defaults 0 0
                      /dev/mapper/VG--MIQ-lv_swap                  swap swap   defaults 0 0
                           /dev/vg_stuff/lv_stuff            /somewhere  xfs rw,noatime 0 0
      END_OF_FSTAB
      expect(File).to receive(:write).with("/etc/fstab", new_content)

      ManageIQ::ApplianceConsole::LogicalVolumeManagement.new(:disk => "/dev/sdb", :mount_point => "/somewhere", :name => "stuff").send(:update_fstab)
    end

    it "updates existing entries" do
      new_content = <<~END_OF_FSTAB

        # /etc/fstab
        # Created by anaconda on Wed May 29 12:37:40 2019

        # Accessible filesystems, by reference, are maintained under '/dev/disk'
        # See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info

                        /dev/mapper/VG--MIQ-lv_os                     /  xfs   defaults 0 0
        UUID=02bf07b5-2404-4779-b93c-d8eb7f2eedea                 /boot  xfs   defaults 0 0
                      /dev/mapper/VG--MIQ-lv_home                 /home  xfs   defaults 0 0
                       /dev/mapper/VG--MIQ-lv_var                  /var  xfs   defaults 0 0
                   /dev/mapper/VG--MIQ-lv_var_log              /var/log  xfs   defaults 0 0
             /dev/mapper/VG--MIQ-lv_var_log_audit        /var/log/audit  xfs   defaults 0 0
                       /dev/mapper/VG--MIQ-lv_log /var/www/miq/vmdb/log  xfs   defaults 0 0
                      /dev/mapper/VG--MIQ-lv_swap                  swap swap   defaults 0 0
                           /dev/vg_stuff/lv_stuff                  /tmp  xfs rw,noatime 0 0
      END_OF_FSTAB
      expect(File).to receive(:write).with("/etc/fstab", new_content)

      ManageIQ::ApplianceConsole::LogicalVolumeManagement.new(:disk => "/dev/sdb", :mount_point => "/tmp", :name => "stuff").send(:update_fstab)
    end
  end
end
