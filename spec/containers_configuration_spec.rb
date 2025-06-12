describe ManageIQ::ApplianceConsole::ContainersConfiguration do
  let(:disk) { double("LinuxAdmin::Disk", :size => "1", :path => "fake disk") }

  before do
    allow(Process::UID).to receive(:from_name).with("manageiq").and_return(Process.uid)
    allow(Process::GID).to receive(:from_name).with("manageiq").and_return(Process.gid)
    allow(subject).to receive(:clear_screen)
    allow(subject).to receive(:say)
  end

  describe "#ask_questions" do
    it "returns true when the user confirms the updates" do
      expect(subject).to receive(:ask_for_disk).and_return(disk)
      expect(subject).to receive(:agree).with(/Configure a new disk for container storage.*/).and_return(true)
      expect(subject).to receive(:agree).with(/Confirm continue with these upda.*/).and_return(true)
      expect(subject.ask_questions).to be_truthy
    end

    it "returns false when the user does not confirm the updates" do
      expect(subject).to receive(:ask_for_disk).and_return(double("LinuxAdmin::Disk", :size => "1", :path => "fake disk"))
      expect(subject).to receive(:agree).with(/Configure a new disk for container storage.*/).and_return(true)
      expect(subject).to receive(:agree).with(/Confirm continue with these upda.*/).and_return(false)
      expect(subject.ask_questions).to be_falsey
    end
  end

  describe "#activate" do
    context "with no disk selected" do
      it "doesn't create a logical volume" do
        expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).not_to receive(:new)
        expect(subject.activate).to be_truthy
      end
    end

    context "with a disk selected" do
      before { subject.disk = disk }

      it "creates the mount point and logical volume" do
        expect(FileUtils).to receive(:mkdir_p).with(described_class::CONTAINERS_ROOT_DIR)
        expect(FileUtils).to receive(:chown).with(Process.uid, Process.gid, described_class::CONTAINERS_ROOT_DIR)
        expect(ManageIQ::ApplianceConsole::LogicalVolumeManagement).to receive(:new)
          .and_return(double(@spec_name, :setup => true))
        expect(subject.activate).to be_truthy
      end
    end
  end
end
