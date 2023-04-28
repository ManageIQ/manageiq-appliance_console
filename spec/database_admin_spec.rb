require 'tempfile'

# rubocop:disable Layout/TrailingWhitespace
#
# Rational:  Needed for heredoc when testing HighLine output
describe ManageIQ::ApplianceConsole::DatabaseAdmin, :with_ui do
  let(:signal_error)           { ManageIQ::ApplianceConsole::MiqSignalError }
  let(:default_table_excludes) { "metrics_* vim_performance_states event_streams" }

  before do
    allow(ManageIQ::ApplianceConsole::DatabaseConfiguration).to receive(:database_name).and_return("vmdb_production")
  end

  describe "#initialize" do
    it "defaults @action, @backup_type, @database_opts, @delete_agree, and @uri" do
      miq_dba = described_class.new
      expect(miq_dba.action).to         eq(:restore)
      expect(miq_dba.backup_type).to    eq(nil)
      expect(miq_dba.database_opts).to  eq({:dbname => "vmdb_production"})
      expect(miq_dba.delete_agree).to   eq(nil)
      expect(miq_dba.uri).to            eq(nil)
    end
  end

  context "for DB restore" do
    subject { described_class.new(:restore, input, output) }

    describe "#ask_questions" do
      it "asks for file location" do
        expect(subject).to receive(:say).with("Restore Database From Backup\n\n")

        expect(ManageIQ::ApplianceConsole::EvmServer).to receive(:running?).and_return(false)

        expect(subject).to receive(:ask_file_location)
        expect(subject).to receive(:ask_for_tables_to_exclude_in_dump)

        subject.ask_questions
      end

      it "raises MiqSignalError for :restore action if evmserverd is running" do
        allow(ManageIQ::ApplianceConsole::EvmServer).to receive(:running?).and_return(true)
        allow(subject).to receive(:press_any_key)

        expect { subject.ask_questions }.to raise_error signal_error
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
      let(:file)      { Tempfile.new("foo.backup").tap(&:close) }
      let(:prmpt)     { "location of the local restore file" }
      let(:default)   { described_class::DB_RESTORE_FILE }
      let(:errmsg)    { "file that exists" }

      before { subject.instance_variable_set(:@backup_type, "local") }

      context "with no filename given" do
        before do
          # stub validator for default answer, since it probably doesn't exist on
          # the machine running these tests.
          stub_const("#{described_class.name}::LOCAL_FILE_VALIDATOR", ->(_) { true })

          say ""
          expect(subject.ask_file_location).to be_truthy
        end

        it "sets @uri to the default filename" do
          expect(subject.database_opts[:local_file]).to eq(default)
        end
      end

      context "with a valid filename given" do
        before do
          say file.path.to_s
          expect(subject.ask_file_location).to be_truthy
        end

        it "sets @uri to point to the local file" do
          expect(subject.database_opts[:local_file]).to eq(file.path)
        end
      end

      context "with an invalid filename given" do
        let(:bad_filename) { "#{file.path}.bad_mmkay" }

        it "reprompts the user and then properly sets the options" do
          say [bad_filename, file.path.to_s]
          expect(subject.ask_file_location).to be_truthy

          error = "Please provide #{errmsg}"
          expect_heard ["Enter the #{prmpt}: |/tmp/evm_db.backup| ", error, prompt]

          expect(subject.database_opts[:local_file]).to eq(file.path)
        end
      end
    end

    describe "#ask_for_tables_to_exclude_in_dump" do
      let(:uri) { "/tmp/my_db.dump" }

      before do
        subject.instance_variable_set(:@database_opts, {:local_file => uri})
      end

      it "no-ops" do
        expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").never
        expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).never
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
      end

      it "does not modify the @database_opts" do
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
        expect(subject.database_opts).to eq({:local_file => uri})
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)   { "/tmp/my_db.backup" }
      let(:agree) { "y" }

      before do
        subject.instance_variable_set(:@database_opts, {:local_file => uri})
        subject.instance_variable_set(:@delete_agree, true)
        expect(input).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(subject).to receive(:restore).and_return(true) }

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
        before { expect(subject).to receive(:restore).and_return(false) }

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
          expect(subject).to receive(:restore).never
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
      let(:filepath)  { "/file/that/most/certainly/does/not/exist.dump" }
      let(:prmpt)     { "location to save the backup file to" }
      let(:default)   { described_class::DB_RESTORE_FILE }
      let(:errmsg)    { "file that exists" }

      context "with no filename given" do
        it "sets @uri to the default filename" do
          say ""
          expect(subject.ask_file_location).to be_truthy
          expect(subject.database_opts[:local_file]).to eq(default)
        end
      end

      context "with a valid filename given" do
        before do
          say filepath.to_s
          expect(subject.ask_file_location).to be_truthy
        end

        it "sets @uri to point to the local file" do
          expect(subject.database_opts[:local_file]).to eq(filepath)
        end
      end
    end

    describe "#ask_to_delete_backup_after_restore" do
      context "when @backup_type is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@database_opts, {:local_file => uri})
          subject.instance_variable_set(:@backup_type, "local")
        end

        it "no-ops" do
          subject.ask_to_delete_backup_after_restore
          expect_output ""
        end
      end

      context "when @backup_type not is LOCAL_FILE" do
        let(:uri) { described_class::DB_RESTORE_FILE }

        before do
          subject.instance_variable_set(:@database_opts, {:local_file => uri})
          subject.instance_variable_set(:@backup_type, "nfs")
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
        subject.instance_variable_set(:@database_opts, {:local_file => uri})
      end

      it "no-ops" do
        expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").never
        expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).never
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
      end

      it "does not modify the @database_opts" do
        expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
        expect(subject.database_opts).to eq({:local_file => uri})
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)   { "/tmp/my_db.backup" }
      let(:agree) { "y" }

      before do
        subject.instance_variable_set(:@database_opts, {:local_file => uri})
        subject.instance_variable_set(:@delete_agree, true)
        expect(input).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(subject).to receive(:backup).and_return(true) }

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
        before { expect(subject).to receive(:backup).and_return(false) }

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
      let(:filepath)  { "/file/that/most/certainly/does/not/exist.dump" }
      let(:prmpt)     { "location to save the dump file to" }
      let(:default)   { described_class::DB_DEFAULT_DUMP_FILE }
      let(:errmsg)    { "file that exists" }

      context "with no filename given" do
        it "sets @uri to the default filename" do
          say ""
          expect(subject.ask_file_location).to be_truthy
          expect(subject.database_opts[:local_file]).to eq(default)
        end
      end

      context "with a valid filename given" do
        before do
          say filepath
          expect(subject.ask_file_location).to be_truthy
        end

        it "sets @uri to point to the local file" do
          expect(subject.database_opts[:local_file]).to eq(filepath)
        end
      end
    end

    describe "#ask_for_tables_to_exclude_in_dump" do
      let(:uri) { "/tmp/my_db.dump" }

      before do
        subject.instance_variable_set(:@database_opts, {:local_file => uri})
      end

      context "when not excluding tables" do
        it "does not add :exclude_table_data to @database_opts" do
          expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").once.and_call_original
          expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).never

          say "n"
          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy

          expect(subject.database_opts).to eq({:local_file => uri})
        end
      end

      context "when excluding tables" do
        it "asks to input tables, providing an example and sensible defaults" do
          say ["y", "metrics_*"]
          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
          expect_output <<-EXAMPLE.strip_heredoc.chomp
            Would you like to exclude tables in the dump? (Y/N): 
            To exclude tables from the dump, enter them in a space separated
            list.  For example:

                > metrics_* vim_performance_states event_streams

            Enter the tables to exclude: |metrics_* vim_performance_states event_streams| 
          EXAMPLE
        end

        it "adds `:exclude_table_data => ['metrics_*', 'vms']` to @database_opts" do
          expect(subject).to receive(:ask_yn?).with("Would you like to exclude tables in the dump").once.and_call_original
          expect(subject).to receive(:ask_for_many).with("table", "tables to exclude", default_table_excludes, 255, Float::INFINITY).once.and_call_original
          say ["y", "metrics_* vms"]

          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
          expect(subject.database_opts).to eq({:local_file => uri, :exclude_table_data => ["metrics_*", "vms"]})
        end

        it "defaults to 'metrics_* vim_performance_states event_streams'" do
          say ["y", ""]

          expect(subject.ask_for_tables_to_exclude_in_dump).to be_truthy
          expect(subject.database_opts).to eq({:local_file => uri, :exclude_table_data => ["metrics_*", "vim_performance_states", "event_streams"]})
        end
      end
    end

    describe "#confirm_and_execute" do
      let(:uri)   { "/tmp/my_db.dump" }
      let(:agree) { "y" }

      before do
        subject.instance_variable_set(:@database_opts, {:local_file => uri})
        subject.instance_variable_set(:@delete_agree, true)
        expect(input).to receive(:getc)
        allow(File).to receive(:delete)
      end

      def confirm_and_execute
        say agree
        subject.confirm_and_execute
      end

      context "when it is successful" do
        before { expect(subject).to receive(:dump).and_return(true) }

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
        before { expect(subject).to receive(:dump).and_return(false) }

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

  # private, but moved out of prompt and keeping tests around
  describe "#sample_url" do
    it "should show an example for nfs" do
      expect(subject.send(:sample_url)).to match(%r{nfs://})
    end
  end
  # rubocop:enable Layout/TrailingWhitespace

  def expect_custom_prompts(hostname, values)
    expect(I18n).to receive(:t).with("database_admin.prompts", :default => {})
                               .and_return(hostname.to_sym => values)
  end
end
