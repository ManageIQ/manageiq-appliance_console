describe ManageIQ::ApplianceConsole::Utilities do
  context ".disk_usage(file)" do
    require 'fileutils'

    let(:file) { Pathname.new(__dir__).join("empty file").to_s }

    before do
      FileUtils.touch(file)
    end

    after do
      FileUtils.rm_f(file)
    end

    it "handles file with a space" do
      expect(AwesomeSpawn).to receive(:run!)
        .with("df", :params => ["-T", "-P", file])
        .and_return(double(:output => 'good job'))

      expect(AwesomeSpawn).to receive(:run!)
        .with("df", :params => ["-T", "-P", "-i", file])
        .and_return(double(:output => 'good job'))

      described_class.disk_usage(file)
    end
  end

  context ".disk_usage" do
    it "linux" do
      linux_df_output_bytes = <<EOF
Filesystem              Type     1024-blocks    Used Available Capacity Mounted on
/dev/mapper/fedora-root ext4        40185208 5932800  32188024      16% /
devtmpfs                devtmpfs     3961576       0   3961576       0% /dev
tmpfs                   tmpfs        3969532    7332   3962200       1% /dev/shm
tmpfs                   tmpfs        3969532    1144   3968388       1% /run
tmpfs                   tmpfs        3969532       0   3969532       0% /sys/fs/cgroup
tmpfs                   tmpfs        3969532     348   3969184       1% /tmp
/dev/sda1               ext4          487652  131515    326441      29% /boot
/dev/mapper/fedora-home ext4       192360020 9325732 173239936       6% /home
EOF
      linux_df_output_inodes = <<EOF
Filesystem              Type       Inodes  IUsed    IFree IUse% Mounted on
/dev/mapper/fedora-root ext4      2564096 146929  2417167    6% /
devtmpfs                devtmpfs   990394    549   989845    1% /dev
tmpfs                   tmpfs      992383     31   992352    1% /dev/shm
tmpfs                   tmpfs      992383    726   991657    1% /run
tmpfs                   tmpfs      992383     13   992370    1% /sys/fs/cgroup
tmpfs                   tmpfs      992383     38   992345    1% /tmp
/dev/sda1               ext4       128016    385   127631    1% /boot
/dev/mapper/fedora-home ext4     12222464 488787 11733677    4% /home
EOF
      expected = [
        {
          :filesystem          => "/dev/mapper/fedora-root",
          :type                => "ext4",
          :total_bytes         => 41149652992,
          :used_bytes          => 6075187200,
          :available_bytes     => 32960536576,
          :used_bytes_percent  => 16,
          :mount_point         => "/",
          :total_inodes        => 2564096,
          :used_inodes         => 146929,
          :available_inodes    => 2417167,
          :used_inodes_percent => 6
        },
        {
          :filesystem          => "devtmpfs",
          :type                => "devtmpfs",
          :total_bytes         => 4056653824,
          :used_bytes          => 0,
          :available_bytes     => 4056653824,
          :used_bytes_percent  => 0,
          :mount_point         => "/dev",
          :total_inodes        => 990394,
          :used_inodes         => 549,
          :available_inodes    => 989845,
          :used_inodes_percent => 1
        },
        {
          :filesystem          => "tmpfs",
          :type                => "tmpfs",
          :total_bytes         => 4064800768,
          :used_bytes          => 7507968,
          :available_bytes     => 4057292800,
          :used_bytes_percent  => 1,
          :mount_point         => "/dev/shm",
          :total_inodes        => 992383,
          :used_inodes         => 38,
          :available_inodes    => 992345,
          :used_inodes_percent => 1
        },
        {
          :filesystem          => "/dev/sda1",
          :type                => "ext4",
          :total_bytes         => 499355648,
          :used_bytes          => 134671360,
          :available_bytes     => 334275584,
          :used_bytes_percent  => 29,
          :mount_point         => "/boot",
          :total_inodes        => 128016,
          :used_inodes         => 385,
          :available_inodes    => 127631,
          :used_inodes_percent => 1
        },
        {
          :filesystem          => "/dev/mapper/fedora-home",
          :type                => "ext4",
          :total_bytes         => 196976660480,
          :used_bytes          => 9549549568,
          :available_bytes     => 177397694464,
          :used_bytes_percent  => 6,
          :mount_point         => "/home",
          :total_inodes        => 12222464,
          :used_inodes         => 488787,
          :available_inodes    => 11733677,
          :used_inodes_percent => 4
        }
      ]

      expect(AwesomeSpawn).to receive(:run!)
        .with("df", :params => ["-T", "-P", "-l"])
        .and_return(double(:output => linux_df_output_bytes))
      expect(AwesomeSpawn).to receive(:run!)
        .with("df", :params => ["-T", "-P", "-i", "-l"])
        .and_return(double(:output => linux_df_output_inodes))

      expect(described_class.disk_usage).to eq(expected)
    end
  end
end
