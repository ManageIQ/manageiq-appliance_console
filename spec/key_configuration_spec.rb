describe ManageIQ::ApplianceConsole::KeyConfiguration do
  before do
    allow(Process::UID).to receive(:from_name).with("manageiq").and_return(Process.uid)
    allow(Process::GID).to receive(:from_name).with("manageiq").and_return(Process.gid)
  end

  context "#ask_questions" do
    subject { Class.new(described_class).tap { |c| c.include(ManageIQ::ApplianceConsole::Prompts) }.new }

    context "creating" do
      it "asks for nothing else" do
        v2_exists(false)
        expect(subject).to receive(:ask_with_menu).with(/key/i, anything, :create, false).and_return(:create)
        expect(subject).not_to receive(:just_ask)
        expect(subject.ask_questions).to be_truthy
      end

      it "defaults to action" do
        v2_exists(false)
        subject.action = :fetch
        expect(subject).to receive(:ask_with_menu).with(/key/i, anything, :fetch, false).and_return(:create)
        expect(subject).not_to receive(:just_ask)
        expect(subject.ask_questions).to be_truthy
      end
    end

    context "fetch" do
      it "asks for other parameters" do
        v2_exists(false)
        expect(subject).to receive(:ask_with_menu).with(/key/i, anything, :create, false).and_return(:fetch)
        expect(subject).to receive(:say).with("")
        expect(subject).to receive(:just_ask).with(/host/i, nil, anything, anything).and_return("newhost")
        expect(subject).to receive(:just_ask).with(/login/i, "root").and_return("root")
        expect(subject).to receive(:just_ask).with(/password/i, nil).and_return("password")
        expect(subject).to receive(:just_ask).with(/path/i, /v2_key$/).and_return("/remote/path/v2_key")
        expect(subject.ask_questions).to be_truthy
      end
    end

    context "with existing key" do
      it "fails if dont overwrite" do
        v2_exists
        expect(subject).to receive(:agree).with(/overwrite/i).and_return(false)
        expect(subject).not_to receive(:ask_with_menu)
        expect(subject.ask_questions).not_to be_truthy
      end

      it "succeeds if overwrite" do
        v2_exists
        expect(subject).to receive(:agree).with(/overwrite/i).and_return(true)
        expect(subject).to receive(:ask_with_menu).and_return(:create)
        expect(subject.ask_questions).to be_truthy
        expect(subject.force).to be_truthy
      end
    end
  end

  context "with host defined" do
    let(:host) { "master.miqmachines.com" }
    let(:password) { "super secret" }
    subject { described_class.new(:action => :fetch, :host => host, :password => password) }

    context "#activate" do
      context "with no existing key" do
        it "fetches key" do
          v2_exists(false) # before download
          v2_exists(true)  # after downloaded
          expect(Net::SCP).to receive(:start).with(host, "root", :password => password)
          expect(FileUtils).to receive(:mv).with(/v2_key\.tmp/, /v2_key$/, :force=>true).and_return(true)
          expect(FileUtils).to receive(:chmod).with(0o400, /v2_key/).and_return(["v2_key"])
          expect(File).to receive(:chown).with(Process.uid, Process.gid, /v2_key\.tmp/)
          expect(subject.activate).to be_truthy
        end

        it "creates key" do
          subject.action = :create
          v2_exists(false)
          expect(ManageIQ::Password).to receive(:generate_symmetric).and_return(154)
          expect(FileUtils).to receive(:mv).with(/v2_key\.tmp/, /v2_key$/, :force=>true).and_return(true)
          expect(FileUtils).to receive(:chmod).with(0o400, /v2_key/).and_return(["v2_key"])
          expect(File).to receive(:chown).with(Process.uid, Process.gid, /v2_key\.tmp/).and_return(0)
          expect(subject.activate).to be_truthy
        end
      end

      context "with existing key" do
        it "removes existing key" do
          subject.force = true
          v2_exists(true) # before downloaded
          v2_exists(true) # after downloaded
          scp = double('scp')
          expect(scp).to receive(:download!).with(subject.key_path, /v2_key/).and_return(:result)
          expect(Net::SCP).to receive(:start).with(host, "root", :password => password).and_yield(scp).and_return(true)
          expect(FileUtils).to receive(:mv).with(/v2_key\.tmp/, /v2_key$/, :force=>true).and_return(true)
          expect(FileUtils).to receive(:chmod).with(0o400, /v2_key/).and_return(["v2_key"])
          expect(File).to receive(:chown).with(Process.uid, Process.gid, /v2_key\.tmp/)
          expect(subject.activate).to be_truthy
        end

        it "fails if key exists (no force)" do
          expect($stderr).to receive(:puts).at_least(2).times
          subject.force = false
          v2_exists(true)
          expect(FileUtils).not_to receive(:mv)
          expect(Net::SCP).not_to receive(:start)
          expect(subject.activate).to be_falsey
        end

        it "keeps original v2_key if fetch new fails" do
          subject.force = true
          key_content = "The v2_key is abc"
          mock_key = Tempfile.new('v2_key')
          mock_key.print(key_content)
          mock_key.close
          stub_const("ManageIQ::ApplianceConsole::KEY_FILE", mock_key.path)
          stub_const("ManageIQ::ApplianceConsole::NEW_KEY_FILE", mock_key.path + ".tmp")
          expect(subject).to receive(:fetch_key).and_return(false)
          expect(subject.activate).to be_falsey
          expect(FileUtils).not_to receive(:mv)
          expect(File.open(ManageIQ::ApplianceConsole::KEY_FILE).read).to eq(key_content)
          mock_key.unlink
        end
      end
    end
  end

  private

  def v2_exists(value = true)
    expect(File).to receive(:exist?).with(/v2/).and_return(value)
  end
end
