describe ManageIQ::ApplianceConsole::LogfileConfiguration do
  let(:original_miq_logs_conf) do
    <<-EOT.strip_heredoc
      /var/www/miq/vmdb/log/*.log /var/www/miq/vmdb/log/apache/*.log {
        daily
        dateext
        missingok
        rotate 14
        notifempty
        compress
        copytruncate
        prerotate
          source /etc/default/evm; /bin/sh ${APPLIANCE_SOURCE_DIRECTORY}/logrotate_free_space_check.sh $1
        endscript
        lastaction
          /sbin/service httpd reload > /dev/null 2>&1 || true
        endscript
      }
    EOT
  end

  let(:miq_logs_conf) { Tempfile.new(@spec_name.downcase) }

  before do
    allow(ManageIQ::ApplianceConsole::EvmServer).to receive(:running?).and_return(true)
    @httpd = LinuxAdmin::Service.new("httpd")
    allow(@httpd).to receive(:running?).and_return(true)
    allow(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(@httpd)
    @spec_name = File.basename(__FILE__).split(".rb").first.freeze
    stub_const("ManageIQ::ApplianceConsole::LogfileConfiguration::MIQ_LOGS_CONF", miq_logs_conf)
    miq_logs_conf.write(original_miq_logs_conf)
    miq_logs_conf.close

    allow(ManageIQ::ApplianceConsole::Utilities).to receive(:disk_usage).and_return([{:total_bytes => "4"}])
    allow(subject).to receive(:clear_screen)
    allow(subject).to receive(:say)
  end

  after do
    FileUtils.rm_f(miq_logs_conf.path)
  end

  describe "#ask_questions" do
    it "returns true when the user confirms the updates" do
      expect(subject).to receive(:ask_for_integer).and_return(99)
      expect(subject).to receive(:ask_for_disk).and_return(double(@spec_name, :size => "9999999", :path => "fake disk"))
      expect(subject).to receive(:agree).with(/Change the saved logrotate count.*/).and_return(true)
      expect(subject).to receive(:agree).with(/Configure a new logfile disk vol.*/).and_return(true)
      expect(subject).to receive(:agree).with(/Confirm continue with these upda.*/).and_return(true)
      expect(subject.ask_questions).to be true
    end

    it "returns false when the user does not confirm the updates" do
      expect(subject).to receive(:ask_for_integer).and_return(99)
      expect(subject).to receive(:ask_for_disk).and_return(double(@spec_name, :size => "9999999", :path => "fake disk"))
      expect(subject).to receive(:agree).with(/Change the saved logrotate count.*/).and_return(true)
      expect(subject).to receive(:agree).with(/Configure a new logfile disk vol.*/).and_return(true)
      expect(subject).to receive(:agree).with(/Confirm continue with these upda.*/).and_return(false)
      expect(subject.ask_questions).to be false
    end

    it "returns false when the user did not request a new disk or a new logrotate count" do
      expect(subject).to_not receive(:ask_for_integer)
      expect(subject).to_not receive(:ask_for_disk)
      expect(subject).to receive(:agree).with(/Change the saved logrotate count.*/).and_return(false)
      expect(subject).to receive(:agree).with(/Configure a new logfile disk vol.*/).and_return(false)
      expect(subject).to_not receive(:agree).with(/Confirm continue with these upda.*/)
      expect(subject.ask_questions).to be false
    end
  end

  describe "#activate" do
    let(:expected_miq_logs_conf) do
      <<-EOT.strip_heredoc
        /var/www/miq/vmdb/log/*.log /var/www/miq/vmdb/log/apache/*.log {
          daily
          dateext
          missingok
          rotate 3
          notifempty
          compress
          copytruncate
          prerotate
            source /etc/default/evm; /bin/sh ${APPLIANCE_SOURCE_DIRECTORY}/logrotate_free_space_check.sh $1
          endscript
          lastaction
            /sbin/service httpd reload > /dev/null 2>&1 || true
          endscript
        }
      EOT
    end

    it "when evm was running, stops and starts evm and configures the logfile disk" do
      subject.new_logrotate_count = 3
      subject.disk = double(@spec_name, :size => "9999999", :path => "fake disk")

      expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).to receive(:new)
        .and_return(double(@spec_name, :setup => true))
      expect(File).to receive(:executable?).with("/sbin/restorecon").and_return(true)
      expect(AwesomeSpawn).to receive(:run!).with('/sbin/restorecon -R -v /var/www/miq/vmdb/log')
      expect(FileUtils).to receive(:mkdir_p)
        .with("#{ManageIQ::ApplianceConsole::LogfileConfiguration::LOGFILE_DIRECTORY}/apache")
      expect(ManageIQ::ApplianceConsole::EvmServer).to receive(:stop)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(@httpd)
      expect(@httpd).to receive(:stop)
      expect(AwesomeSpawn).to receive(:run!)
        .with('/usr/sbin/semanage fcontext -a -t httpd_log_t "#{LOGFILE_DIRECTORY.to_path}(/.*)?"')
      expect(ManageIQ::ApplianceConsole::EvmServer).to receive(:start).with(:enable => true)
      expect(LinuxAdmin::Service).to receive(:new).with("httpd").and_return(@httpd)
      expect(@httpd).to receive_message_chain(:enable, :start)
      expect(subject.activate).to be true
      expect(File.read(miq_logs_conf)).to eq(expected_miq_logs_conf)
    end

    it "when evm was not running, configures the logfile disk but does not stops and starts evm" do
      subject.evm_was_running = false
      subject.new_logrotate_count = 3
      subject.disk = double(@spec_name, :size => "9999999", :path => "fake disk")

      expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).to receive(:new)
        .and_return(double(@spec_name, :setup => true))
      expect(File).to receive(:executable?).with("/sbin/restorecon").and_return(true)
      expect(AwesomeSpawn).to receive(:run!).with('/sbin/restorecon -R -v /var/www/miq/vmdb/log')
      expect(FileUtils).to receive(:mkdir_p)
        .with("#{ManageIQ::ApplianceConsole::LogfileConfiguration::LOGFILE_DIRECTORY}/apache")
      expect(AwesomeSpawn).to receive(:run!)
        .with('/usr/sbin/semanage fcontext -a -t httpd_log_t "#{LOGFILE_DIRECTORY.to_path}(/.*)?"')
      expect(LinuxAdmin::Service).to_not receive(:new)

      expect(subject.activate).to be true
      expect(File.read(miq_logs_conf)).to eq(expected_miq_logs_conf)
    end
  end
end
