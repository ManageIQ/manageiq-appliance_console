require 'tempfile'

# rubocop:disable Layout/TrailingWhitespace
#
# Rational:  Needed for heredoc when testing HighLine output
describe ManageIQ::ApplianceConsole::DatabaseAdmin, :with_ui do
  let(:signal_error)           { ManageIQ::ApplianceConsole::MiqSignalError }
  let(:default_table_excludes) { "metrics_* vim_performance_states event_streams" }

  describe "#initialize" do
    it "defaults @action, @backup_type, @task, @task_params, @delete_agree, and @uri" do
      miq_dba = described_class.new
      expect(miq_dba.action).to       eq(:restore)
      expect(miq_dba.backup_type).to  eq(nil)
      expect(miq_dba.task).to         eq(nil)
      expect(miq_dba.task_params).to  eq([])
      expect(miq_dba.delete_agree).to eq(nil)
      expect(miq_dba.uri).to          eq(nil)
    end
  end

  context "for DB restore" do
    subject { described_class.new(:restore, input, output) }

    describe "#ask_questions" do
      it "asks for file location" do
        expect(subject).to receive(:say).with("Restore Database From Backup\n\n")
        expect(subject).to receive(:ask_file_location)
        expect(subject).to receive(:ask_for_tables_to_exclude_in_dump)

        subject.ask_questions
      end
    end

    describe "#activate" do
      it "asks to delete backup and runs restore" do
        expect(subject).to receive(:clear_screen)
        expect(subject).to receive(:say).with("Restore Database From Backup\n\n")
        expect(subject).to receive(:ask_to_delete_backup_after_restore)
        expect(subject).to receive(:confirm_and_execute)

        subject.activate
      end
    end

    describe "#ask_file_location" do
      it "displays the menu" do
        expect(subject).to receive(:ask_local_file_options).once
        say ""
        subject.ask_file_location
        expect_output <<-PROMPT.strip_heredoc.chomp + " "
          Restore Database File

          1) Local file
          2) Network File System (NFS)
          3) Samba (SMB)
          4) Cancel

          Choose the restore database file: |1|
        PROMPT
      end

      it "defaults to local file" do
        expect(subject).to receive(:ask_local_file_options).once
        say ""
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
      end

      it "calls #ask_local_file_options when choosen" do
        expect(subject).to receive(:ask_local_file_options).once
        say "1"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
      end

      it "calls #ask_nfs_file_options when choosen" do
        expect(subject).to receive(:ask_nfs_file_options).once
        say "2"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::NFS_FILE)
      end

      it "calls #ask_smb_file_options when choosen" do
        expect(subject).to receive(:ask_smb_file_options).once
        say "3"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::SMB_FILE)
      end

      it "cancels when CANCEL option is choosen" do
        say "4"
        expect { subject.ask_file_location }.to raise_error signal_error
      end
    end

    describe "#ask_local_file_options" do
      let(:file)      { Tempfile.new("foo.backup").tap(&:close) }
      let(:prmpt)     { "location of the local restore file" }
      let(:default)   { described_class::DB_RESTORE_FILE }
      let(:errmsg)    { "file that exists" }

      before { subject.instance_variable_set(:@backup_type, described_class::LOCAL_FILE) }

      context "with no filename given" do
        before do
          # stub validator for default answer, since it probably doesn't exist on
          # the machine running these tests.
          stub_const("#{described_class.name}::LOCAL_FILE_VALIDATOR", ->(_) { true })

          say ""
          expect(subject.ask_local_file_options).to be_truthy
        end

        it "sets @uri to the default filename" do
          expect(subject.uri).to eq(default)
        end
      end

      context "with a valid filename given" do
        before do
          say file.path.to_s
          expect(subject.ask_local_file_options).to be_truthy
        end

        it "sets @uri to point to the local file" do
          expect(subject.uri).to eq(file.path)
        end

        it "sets @task to point to 'evm:db:restore:local'" do
          expect(subject.task).to eq("evm:db:restore:local")
        end

        it "sets @task_params to point to the local file" do
          expect(subject.task_params).to eq(["--", {:local_file => file.path}])
        end
      end

      context "with an invalid filename given" do
        let(:bad_filename) { "#{file.path}.bad_mmkay" }

        it "reprompts the user and then properly sets the options" do
          say [bad_filename, file.path.to_s]
          expect(subject.ask_local_file_options).to be_truthy

          error = "Please provide #{errmsg}"
          expect_heard ["Enter the #{prmpt}: ", error, prompt]

          expect(subject.uri).to         eq(file.path)
          expect(subject.task).to        eq("evm:db:restore:local")
          expect(subject.task_params).to eq(["--", {:local_file => file.path}])
        end
      end
    end

    describe "#ask_nfs_file_options" do
      let(:uri)         { File.dirname(subject.sample_url('nfs')) }
      let(:filename)    { File.basename(subject.sample_url('nfs')) }
      let(:example_uri) { File.join(uri, filename) }
      let(:prmpt)       { "location of the remote backup file\nExample: #{example_uri}" }
      let(:errmsg)      { "a valid URI" }

      context "with a valid uri given" do
        before do
          say uri
          expect(subject.ask_nfs_file_options).to be_truthy
        end

        it "sets @uri to point to the nfs share url" do
          expect(subject.uri).to eq(uri)
        end

        it "sets @filename to nil" do
          expect(subject.filename).to eq(nil)
        end

        it "sets @task to point to 'evm:db:restore:remote'" do
          expect(subject.task).to eq("evm:db:restore:remote")
        end

        it "sets @task_params to point to the nfs file" do
          expect(subject.task_params).to eq(["--", {:uri => uri}])
        end
      end

      context "with an invalid uri given" do
        let(:bad_uri) { "file://host.mydomain.com/path/to" }

        it "reprompts the user and then properly sets the options" do
          say [bad_uri, uri]
          expect(subject.ask_nfs_file_options).to be_truthy

          error = "Please provide #{errmsg}"
          expect_heard ["Enter the #{prmpt}: ", error, prompt]

          expect(subject.uri).to         eq(uri)
          expect(subject.filename).to    eq(nil)
          expect(subject.task).to        eq("evm:db:restore:remote")
          expect(subject.task_params).to eq(["--", {:uri => uri}])
        end
      end
    end

    describe "#ask_smb_file_options" do
      let(:example_uri) { subject.sample_url('smb') }
      let(:user)        { 'example.com/admin' }
      let(:pass)        { 'supersecret' }
      let(:uri_prompt)  { "Enter the location of the remote backup file\nExample: #{example_uri}" }
      let(:user_prompt) { "Enter the username with access to this file.\nExample: 'mydomain.com/user'" }
      let(:pass_prompt) { "Enter the password for #{user}" }
      let(:errmsg)      { "a valid URI" }

      let(:expected_task_params) do
        [
          "--",
          {
            :uri          => example_uri,
            :uri_username => user,
            :uri_password => pass
          }
        ]
      end

      context "with a valid uri, username, and password given" do
        before do
          say [example_uri, user, pass]
          expect(subject.ask_smb_file_options).to be_truthy
        end

        it "sets @uri to point to the smb file" do
          expect(subject.uri).to eq(example_uri)
        end

        it "sets @task to point to 'evm:db:restore:local'" do
          expect(subject.task).to eq("evm:db:restore:remote")
        end

        it "sets @task_params to point to the smb file, username, and password" do
          expect(subject.task_params).to eq(expected_task_params)
        end
      end

      context "with a invalid uri given" do
        let(:bad_uri) { "nfs://host.mydomain.com/path/to/file" }

        before do
          say [bad_uri, example_uri, user, pass]
          expect(subject.ask_smb_file_options).to be_truthy
        end

        it "reprompts the user and then properly sets the options" do
          error = "Please provide #{errmsg}"

          expect_readline_question_asked uri_prompt
          expect_readline_question_asked user_prompt
          expect_heard [
            uri_prompt,
            error,
            prompt,
            "#{pass_prompt}: ***********\n"
          ]

          expect(subject.uri).to         eq(example_uri)
          expect(subject.task).to        eq("evm:db:restore:remote")
          expect(subject.task_params).to eq(expected_task_params)
        end
      end
    end

    describe "#ask_to_delete_backup_after_restore" do
      context "when @backup_type is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@uri, uri)
          subject.instance_variable_set(:@backup_type, described_class::LOCAL_FILE)
        end

        it "sets @delete_agree if the user agrees" do
          say "y"
          subject.ask_to_delete_backup_after_restore
          expect_output <<-PROMPT.strip_heredoc.chomp + " "
            The local database restore file is located at: '#{uri}'.
            Should this file be deleted after completing the restore? (Y/N):
          PROMPT
        end

        it "sets @delete_agree to true if the user agrees" do
          say "y"
          subject.ask_to_delete_backup_after_restore
          expect(subject.delete_agree).to eq(true)
        end

        it "sets @delete_agree to false if the user disagrees" do
          say "n"
          subject.ask_to_delete_backup_after_restore
          expect(subject.delete_agree).to eq(false)
        end
      end

      context "when @backup_type not is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@uri, uri)
          subject.instance_variable_set(:@backup_type, described_class::NFS_FILE)
        end

        it "no-ops" do
          subject.ask_to_delete_backup_after_restore
          expect_output ""
        end
      end
    end

    describe "#ask_for_tables_to_exclude_in_dump" do
      let(:uri) { "/tmp/my_db.dump" }

      before do
        subject.instance_variable_set(:@task_params, ["--", { :uri => uri }])
      end

      it "no-ops" do
        expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").never
        expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).never
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
      end

      it "does not modify the @task_params" do
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
        expect(subject.task_params).to eq(["--", {:uri => uri}])
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)             { "/tmp/my_db.backup" }
      let(:agree)           { "y" }
      let(:task)            { "evm:db:restore:local" }
      let(:task_params)     { ["--", { :uri => uri }] }
      let(:utils)           { ManageIQ::ApplianceConsole::Utilities }

      before do
        subject.instance_variable_set(:@uri, uri)
        subject.instance_variable_set(:@delete_agree, true)
        expect(STDIN).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(utils).to receive(:rake).and_return(true) }

        it "deletes the backup file" do
          expect(File).to receive(:delete).with(uri).once
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
            Are you sure you would like to restore the database? (Y/N): 
            Restoring the database...

            Removing the database restore file #{uri}...

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the backup file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
              Are you sure you would like to restore the database? (Y/N): 
              Restoring the database...

              Press any key to continue.
            PROMPT
          end
        end
      end

      context "when it is not successful" do
        before { expect(utils).to receive(:rake).and_return(false) }

        it "does not delete the backup file" do
          expect(File).to receive(:delete).with(uri).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
            Are you sure you would like to restore the database? (Y/N): 
            Restoring the database...

            Database restore failed. Check the logs for more information

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the backup file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
              Are you sure you would like to restore the database? (Y/N): 
              Restoring the database...

              Database restore failed. Check the logs for more information

              Press any key to continue.
            PROMPT
          end
        end
      end

      context "when the user aborts" do
        let(:agree) { 'n' }

        it "does not delete the backup file" do
          expect(File).to  receive(:delete).with(uri).never
          expect(utils).to receive(:rake).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Note: A database restore cannot be undone.  The restore will use the file: #{uri}.
            Are you sure you would like to restore the database? (Y/N): 
            Press any key to continue.
          PROMPT
        end
      end
    end
  end

  context "for DB backup" do
    subject { described_class.new(:backup, input, output) }

    describe "#ask_questions" do
      it "asks for file location" do
        expect(subject).to receive(:say).with("Create Database Backup\n\n")
        expect(subject).to receive(:ask_file_location)
        expect(subject).to receive(:ask_for_tables_to_exclude_in_dump)

        subject.ask_questions
      end
    end

    describe "#activate" do
      it "asks to delete backup and runs restore" do
        expect(subject).to receive(:clear_screen)
        expect(subject).to receive(:say).with("Create Database Backup\n\n")
        expect(subject).to receive(:ask_to_delete_backup_after_restore)
        expect(subject).to receive(:confirm_and_execute)

        subject.activate
      end
    end

    describe "#ask_file_location" do
      it "displays the menu" do
        expect(subject).to receive(:ask_local_file_options).once
        say ""
        subject.ask_file_location
        expect_output <<-PROMPT.strip_heredoc.chomp + " "
          Backup Output File Name

          1) Local file
          2) Network File System (NFS)
          3) Samba (SMB)
          4) Cancel

          Choose the backup output file name: |1|
        PROMPT
      end

      it "defaults to local file" do
        expect(subject).to receive(:ask_local_file_options).once
        say ""
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
      end

      it "calls #ask_local_file_options when choosen" do
        expect(subject).to receive(:ask_local_file_options).once
        say "1"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
      end

      it "calls #ask_nfs_file_options when choosen" do
        expect(subject).to receive(:ask_nfs_file_options).once
        say "2"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::NFS_FILE)
      end

      it "calls #ask_smb_file_options when choosen" do
        expect(subject).to receive(:ask_smb_file_options).once
        say "3"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::SMB_FILE)
      end

      it "cancels when CANCEL option is choosen" do
        say "4"
        expect { subject.ask_file_location }.to raise_error signal_error
      end
    end

    describe "#ask_local_file_options" do
      let(:filepath)  { "/file/that/most/certainly/does/not/exist.dump" }
      let(:prmpt)     { "location to save the backup file to" }
      let(:default)   { described_class::DB_RESTORE_FILE }
      let(:errmsg)    { "file that exists" }

      context "with no filename given" do
        it "sets @uri to the default filename" do
          say ""
          expect(subject.ask_local_file_options).to be_truthy
          expect(subject.uri).to eq(default)
        end
      end

      context "with a valid filename given" do
        before do
          say filepath.to_s
          expect(subject.ask_local_file_options).to be_truthy
        end

        it "sets @uri to point to the local file" do
          expect(subject.uri).to eq(filepath)
        end

        it "sets @task to point to 'evm:db:backup:local'" do
          expect(subject.task).to eq("evm:db:backup:local")
        end

        it "sets @task_params to point to the local file" do
          expect(subject.task_params).to eq(["--", {:local_file => filepath}])
        end
      end
    end

    describe "#ask_nfs_file_options" do
      let(:uri)         { File.dirname(subject.sample_url('nfs')) }
      let(:filename)    { File.basename(subject.sample_url('nfs')) }
      let(:example_uri) { File.join(uri, filename) }
      let(:prmpt)       { "location to save the remote backup file to\nExample: #{example_uri}" }
      let(:errmsg)      { "a valid URI" }

      context "with a valid uri given" do
        before do
          say [filename, uri]
          expect(subject.ask_nfs_file_options).to be_truthy
        end

        it "sets @uri to point to the nfs share url" do
          expect(subject.uri).to eq(uri)
        end

        it "sets @filename the name of the file on the share" do
          expect(subject.filename).to eq(filename)
        end

        it "sets @task to point to 'evm:db:backup:remote'" do
          expect(subject.task).to eq("evm:db:backup:remote")
        end

        it "sets @task_params to point to the nfs file" do
          expect(subject.task_params).to eq(["--", {:uri => uri, :remote_file_name => filename}])
        end
      end

      context "with an invalid uri given" do
        let(:bad_uri) { "file://host.mydomain.com/path/to" }

        before do
          say ["file", bad_uri, uri]
          expect(subject.ask_nfs_file_options).to be_truthy
        end

        it "reprompts the user and then properly sets the options" do
          error = "Please provide #{errmsg}"
          expect_heard ["Enter the #{prmpt}: ", error, prompt]

          expect(subject.uri).to         eq(uri)
          expect(subject.filename).to    eq("file")
          expect(subject.task).to        eq("evm:db:backup:remote")
          expect(subject.task_params).to eq(["--", {:uri => uri, :remote_file_name => "file"}])
        end
      end
    end

    describe "#ask_smb_file_options" do
      let(:example_uri) { subject.sample_url('smb') }
      let(:user)        { 'example.com/admin' }
      let(:pass)        { 'supersecret' }
      let(:uri_prompt)  { "Enter the location to save the remote backup file to\nExample: #{example_uri}" }
      let(:user_prompt) { "Enter the username with access to this file.\nExample: 'mydomain.com/user'" }
      let(:pass_prompt) { "Enter the password for #{user}" }
      let(:errmsg)      { "a valid URI" }

      let(:expected_task_params) do
        [
          "--",
          {
            :uri          => example_uri,
            :uri_username => user,
            :uri_password => pass
          }
        ]
      end

      context "with a valid uri, username, and password given" do
        before do
          say [example_uri, user, pass]
          expect(subject.ask_smb_file_options).to be_truthy
        end

        it "sets @uri to point to the smb file" do
          expect(subject.uri).to eq(example_uri)
        end

        it "sets @task to point to 'evm:db:backup:local'" do
          expect(subject.task).to eq("evm:db:backup:remote")
        end

        it "sets @task_params to point to the smb file, username, and password" do
          expect(subject.task_params).to eq(expected_task_params)
        end
      end

      context "with a invalid uri given" do
        let(:bad_uri) { "nfs://host.mydomain.com/path/to/file" }

        before do
          say [bad_uri, example_uri, user, pass]
          expect(subject.ask_smb_file_options).to be_truthy
        end

        it "reprompts the user and then properly sets the options" do
          error = "Please provide #{errmsg}"

          expect_readline_question_asked uri_prompt
          expect_readline_question_asked user_prompt
          expect_heard [
            uri_prompt,
            error,
            prompt,
            "#{pass_prompt}: ***********\n"
          ]

          expect(subject.uri).to         eq(example_uri)
          expect(subject.task).to        eq("evm:db:backup:remote")
          expect(subject.task_params).to eq(expected_task_params)
        end
      end
    end

    describe "#ask_to_delete_backup_after_restore" do
      context "when @backup_type is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@uri, uri)
          subject.instance_variable_set(:@backup_type, described_class::LOCAL_FILE)
        end

        it "no-ops" do
          subject.ask_to_delete_backup_after_restore
          expect_output ""
        end
      end

      context "when @backup_type not is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@uri, uri)
          subject.instance_variable_set(:@backup_type, described_class::NFS_FILE)
        end

        it "no-ops" do
          subject.ask_to_delete_backup_after_restore
          expect_output ""
        end
      end
    end

    describe "#ask_for_tables_to_exclude_in_dump" do
      let(:uri) { "/tmp/my_db.dump" }

      before do
        subject.instance_variable_set(:@task_params, ["--", { :uri => uri }])
      end

      it "no-ops" do
        expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").never
        expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).never
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
      end

      it "does not modify the @task_params" do
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
        expect(subject.task_params).to eq(["--", {:uri => uri}])
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)             { "/tmp/my_db.backup" }
      let(:agree)           { "y" }
      let(:task)            { "evm:db:backup:local" }
      let(:task_params)     { ["--", { :uri => uri }] }
      let(:utils)           { ManageIQ::ApplianceConsole::Utilities }

      before do
        subject.instance_variable_set(:@uri, uri)
        subject.instance_variable_set(:@delete_agree, true)
        expect(STDIN).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(utils).to receive(:rake).and_return(true) }

        it "does not delete the backup file" do
          expect(File).to receive(:delete).with(uri).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Running Database backup to /tmp/my_db.backup...

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the backup file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Running Database backup to /tmp/my_db.backup...

              Press any key to continue.
            PROMPT
          end
        end
      end

      context "when it is not successful" do
        before { expect(utils).to receive(:rake).and_return(false) }

        it "does not delete the backup file" do
          expect(File).to receive(:delete).with(uri).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Running Database backup to /tmp/my_db.backup...

            Database backup failed. Check the logs for more information

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the backup file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Running Database backup to /tmp/my_db.backup...

              Database backup failed. Check the logs for more information

              Press any key to continue.
            PROMPT
          end
        end
      end
    end
  end

  context "for DB dump" do
    subject { described_class.new(:dump, input, output) }

    describe "#ask_questions" do
      let(:pg_dump_warning) do
        <<-WARN.strip_heredoc
          WARNING:  This is not the recommended and supported way of running a
          database backup, and is strictly meant for exporting a database for
          support/debugging purposes!


        WARN
      end

      it "warns about using pg_dump and asks for file location" do
        expect(subject).to receive(:say).with("Create Database Dump\n\n")
        expect(subject).to receive(:say).with(pg_dump_warning)
        expect(subject).to receive(:ask_file_location)
        expect(subject).to receive(:ask_for_tables_to_exclude_in_dump)

        subject.ask_questions
      end

      it "has proper formatting for the pg_dump warning" do
        allow(subject).to receive(:ask_file_location)
        allow(subject).to receive(:ask_for_tables_to_exclude_in_dump)
        subject.ask_questions

        expect_output <<-PROMPT.strip_heredoc
          Create Database Dump

          WARNING:  This is not the recommended and supported way of running a
          database backup, and is strictly meant for exporting a database for
          support/debugging purposes!


        PROMPT
      end
    end

    describe "#activate" do
      it "asks to delete backup and runs dump" do
        expect(subject).to receive(:clear_screen)
        expect(subject).to receive(:say).with("Create Database Dump\n\n")
        expect(subject).to receive(:ask_to_delete_backup_after_restore)
        expect(subject).to receive(:confirm_and_execute)

        subject.activate
      end
    end

    describe "#ask_file_location" do
      it "displays the menu" do
        expect(subject).to receive(:ask_local_file_options).once
        say ""
        subject.ask_file_location
        expect_output <<-PROMPT.strip_heredoc.chomp + " "
          Dump Output File Name

          1) Local file
          2) Network File System (NFS)
          3) Samba (SMB)
          4) Cancel

          Choose the dump output file name: |1|
        PROMPT
      end

      it "defaults to local file" do
        expect(subject).to receive(:ask_local_file_options).once
        say ""
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
      end

      it "calls #ask_local_file_options when choosen" do
        expect(subject).to receive(:ask_local_file_options).once
        say "1"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::LOCAL_FILE)
      end

      it "calls #ask_nfs_file_options when choosen" do
        expect(subject).to receive(:ask_nfs_file_options).once
        say "2"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::NFS_FILE)
      end

      it "calls #ask_smb_file_options when choosen" do
        expect(subject).to receive(:ask_smb_file_options).once
        say "3"
        subject.ask_file_location
        expect(subject.backup_type).to eq(described_class::SMB_FILE)
      end

      it "cancels when CANCEL option is choosen" do
        say "4"
        expect { subject.ask_file_location }.to raise_error signal_error
      end
    end

    describe "#ask_local_file_options" do
      let(:filepath)  { "/file/that/most/certainly/does/not/exist.dump" }
      let(:prmpt)     { "location to save the dump file to" }
      let(:default)   { described_class::DB_DEFAULT_DUMP_FILE }
      let(:errmsg)    { "file that exists" }

      context "with no filename given" do
        it "sets @uri to the default filename" do
          say ""
          expect(subject.ask_local_file_options).to be_truthy
          expect(subject.uri).to eq(default)
        end
      end

      context "with a valid filename given" do
        before do
          say filepath
          expect(subject.ask_local_file_options).to be_truthy
        end

        it "sets @uri to point to the local file" do
          expect(subject.uri).to eq(filepath)
        end

        it "sets @task to point to 'evm:db:dump:local'" do
          expect(subject.task).to eq("evm:db:dump:local")
        end

        it "sets @task_params to point to the local file" do
          expect(subject.task_params).to eq(["--", {:local_file => filepath}])
        end
      end
    end

    describe "#ask_nfs_file_options" do
      let(:uri)         { File.dirname(subject.sample_url('nfs')) }
      let(:filename)    { File.basename(subject.sample_url('nfs')) }
      let(:example_uri) { File.join(uri, filename) }
      let(:prmpt)       { "location to save the remote dump file to\nExample: #{example_uri}" }
      let(:errmsg)      { "a valid URI" }

      context "with a valid uri given" do
        before do
          say [filename, uri]
          expect(subject.ask_nfs_file_options).to be_truthy
        end

        it "sets @uri to point to the nfs share url" do
          expect(subject.uri).to eq(uri)
        end

        it "sets @filename the name of the file on the share" do
          expect(subject.filename).to eq(filename)
        end

        it "sets @task to point to 'evm:db:dump:remote'" do
          expect(subject.task).to eq("evm:db:dump:remote")
        end

        it "sets @task_params to point to the nfs file" do
          expect(subject.task_params).to eq(["--", {:uri => uri, :remote_file_name => filename}])
        end
      end

      context "with an invalid uri given" do
        let(:bad_uri) { "file://host.mydomain.com/path/to" }

        it "reprompts the user and then properly sets the options" do
          say ["file", bad_uri, uri]
          expect(subject.ask_nfs_file_options).to be_truthy

          error = "Please provide #{errmsg}"
          expect_heard ["Enter the #{prmpt}: ", error, prompt]

          expect(subject.uri).to         eq(uri)
          expect(subject.filename).to    eq("file")
          expect(subject.task).to        eq("evm:db:dump:remote")
          expect(subject.task_params).to eq(["--", {:uri => uri, :remote_file_name => "file"}])
        end
      end
    end

    describe "#ask_smb_file_options" do
      let(:example_uri) { subject.sample_url('smb') }
      let(:user)        { 'example.com/admin' }
      let(:pass)        { 'supersecret' }
      let(:uri_prompt)  { "Enter the location to save the remote dump file to\nExample: #{example_uri}" }
      let(:user_prompt) { "Enter the username with access to this file.\nExample: 'mydomain.com/user'" }
      let(:pass_prompt) { "Enter the password for #{user}" }
      let(:errmsg)      { "a valid URI" }

      let(:expected_task_params) do
        [
          "--",
          {
            :uri          => example_uri,
            :uri_username => user,
            :uri_password => pass
          }
        ]
      end

      context "with a valid uri, username, and password given" do
        before do
          say [example_uri, user, pass]
          expect(subject.ask_smb_file_options).to be_truthy
        end

        it "sets @uri to point to the smb file" do
          expect(subject.uri).to eq(example_uri)
        end

        it "sets @task to point to 'evm:db:dump:local'" do
          expect(subject.task).to eq("evm:db:dump:remote")
        end

        it "sets @task_params to point to the smb file, username, and password" do
          expect(subject.task_params).to eq(expected_task_params)
        end
      end

      context "with a invalid uri given" do
        let(:bad_uri) { "nfs://host.mydomain.com/path/to/file" }

        before do
          say [bad_uri, example_uri, user, pass]
          expect(subject.ask_smb_file_options).to be_truthy
        end

        it "reprompts the user and then properly sets the options" do
          error = "Please provide #{errmsg}"

          expect_readline_question_asked uri_prompt
          expect_readline_question_asked user_prompt
          expect_heard [
            uri_prompt,
            error,
            prompt,
            "#{pass_prompt}: ***********\n"
          ]

          expect(subject.uri).to         eq(example_uri)
          expect(subject.task).to        eq("evm:db:dump:remote")
          expect(subject.task_params).to eq(expected_task_params)
        end
      end
    end

    describe "#ask_to_delete_backup_after_restore" do
      context "when @backup_type is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@uri, uri)
          subject.instance_variable_set(:@backup_type, described_class::LOCAL_FILE)
        end

        it "no-ops" do
          subject.ask_to_delete_backup_after_restore
          expect_output ""
        end
      end

      context "when @backup_type not is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@uri, uri)
          subject.instance_variable_set(:@backup_type, described_class::NFS_FILE)
        end

        it "no-ops" do
          subject.ask_to_delete_backup_after_restore
          expect_output ""
        end
      end
    end

    describe "#ask_for_tables_to_exclude_in_dump" do
      let(:uri) { "/tmp/my_db.dump" }

      before do
        subject.instance_variable_set(:@task_params, ["--", { :uri => uri }])
      end

      context "when not excluding tables" do
        it "does not add :exclude-table-data to @task_params" do
          expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").once.and_call_original
          expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).never

          say "n"
          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy

          expect(subject.task_params).to eq(["--", {:uri => uri}])
        end
      end

      context "when excluding tables" do
        it "asks to input tables, providing an example and sensible defaults" do
          say ["y", "metrics_*"]
          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
          expect_output <<-EXAMPLE.strip_heredoc

            To exclude tables from the dump, enter them in a space separated
            list.  For example:

                > metrics_* vim_performance_states event_streams

          EXAMPLE
          expect_readline_question_asked <<-PROMPT.strip_heredoc.chomp
            Would you like to exclude tables in the dump? (Y/N): y
            Enter the tables to exclude: |metrics_* vim_performance_states event_streams|
          PROMPT
        end

        it "adds `:exclude-table-data => ['metrics_*', 'vms']` to @task_params" do
          expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").once.and_call_original
          expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).once.and_call_original
          say ["y", "metrics_* vms"]

          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
          expect(subject.task_params).to eq(["--", {:uri => uri, :"exclude-table-data" => ["metrics_*", "vms"]}])
        end

        it "defaults to 'metrics_* vim_performance_states event_streams'" do
          say ["y", ""]

          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
          expect(subject.task_params).to eq(["--", {:uri => uri, :"exclude-table-data" => ["metrics_*", "vim_performance_states", "event_streams"]}])
        end
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)             { "/tmp/my_db.dump" }
      let(:agree)           { "y" }
      let(:task)            { "evm:db:dump:local" }
      let(:task_params)     { ["--", { :uri => uri }] }
      let(:utils)           { ManageIQ::ApplianceConsole::Utilities }

      before do
        subject.instance_variable_set(:@uri, uri)
        subject.instance_variable_set(:@delete_agree, true)
        expect(STDIN).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(utils).to receive(:rake).and_return(true) }

        it "does not delete the dump file" do
          expect(File).to receive(:delete).with(uri).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Running Database dump to /tmp/my_db.dump...

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the dump file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Running Database dump to /tmp/my_db.dump...

              Press any key to continue.
            PROMPT
          end
        end
      end

      context "when it is not successful" do
        before { expect(utils).to receive(:rake).and_return(false) }

        it "does not delete the dump file" do
          expect(File).to receive(:delete).with(uri).never
          confirm_and_execute
        end

        it "outputs waits for user to press a key to continue" do
          confirm_and_execute
          expect_output <<-PROMPT.strip_heredoc

            Running Database dump to /tmp/my_db.dump...

            Database dump failed. Check the logs for more information

            Press any key to continue.
          PROMPT
        end

        context "without a delete agreement" do
          before do
            subject.instance_variable_set(:@delete_agree, false)
          end

          it "does not delete the dump file" do
            expect(File).to receive(:delete).with(uri).never
            confirm_and_execute
          end

          it "outputs waits for user to press a key to continue" do
            confirm_and_execute
            expect_output <<-PROMPT.strip_heredoc

              Running Database dump to /tmp/my_db.dump...

              Database dump failed. Check the logs for more information

              Press any key to continue.
            PROMPT
          end
        end
      end
    end
  end
end
# rubocop:enable Layout/TrailingWhitespace
