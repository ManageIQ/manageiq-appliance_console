require 'manageiq/appliance_console/errors'

module ManageIQ
  module ApplianceConsole
    class DatabaseAdmin < HighLine
      include ManageIQ::ApplianceConsole::Prompts

      LOCAL_FILE     = "Local file".freeze
      NFS_FILE       = "Network File System (NFS)".freeze
      SMB_FILE       = "Samba (SMB)".freeze
      FILE_OPTIONS   = [LOCAL_FILE, NFS_FILE, SMB_FILE, CANCEL].freeze
      FILE_MENU_ARGS = ["Restore Database File", FILE_OPTIONS, LOCAL_FILE, nil].freeze

      DB_RESTORE_FILE      = "/tmp/evm_db.backup".freeze
      LOCAL_FILE_VALIDATOR = ->(a) { File.exist?(a) }.freeze

      NFS_PROMPT = <<-PROMPT.strip_heredoc.chomp
        location of the remote backup file
        Example: #{SAMPLE_URLS['nfs']}
      PROMPT
      SMB_PROMPT = <<-PROMPT.strip_heredoc.chomp
        location of the remote backup file
        Example: #{SAMPLE_URLS['smb']}
      PROMPT
      USER_PROMPT = <<-PROMPT.strip_heredoc.chomp
        username with access to this file.
        Example: 'mydomain.com/user'
      PROMPT

      attr_accessor :backup_type, :task, :task_params, :delete_agree, :uri

      def initialize(input = $stdin, output = $stdout)
        super
        @task_params = []
      end

      def ask_questions
        setting_header
        ask_file_location
      end

      def activate
        clear_screen
        setting_header

        ask_to_delete_backup_after_restore
        confirm_and_execute
      end

      def ask_file_location
        case @backup_type = ask_with_menu(*FILE_MENU_ARGS)
        when LOCAL_FILE then ask_local_file_options
        when NFS_FILE   then ask_nfs_file_options
        when SMB_FILE   then ask_smb_file_options
        when CANCEL     then raise MiqSignalError
        end
      end

      def ask_local_file_options
        @uri = just_ask("location of the local restore file",
                        DB_RESTORE_FILE, LOCAL_FILE_VALIDATOR,
                        "file that exists")

        @task        = "evm:db:restore:local"
        @task_params = ["--", {:local_file => uri}]
      end

      def ask_nfs_file_options
        @uri         = ask_for_uri(NFS_PROMPT, "nfs")
        @task        = "evm:db:restore:remote"
        @task_params = ["--", {:uri => uri}]
      end

      def ask_smb_file_options
        @uri         = ask_for_uri(SMB_PROMPT, "smb")
        user         = just_ask(USER_PROMPT)
        pass         = ask_for_password("password for #{user}")

        @task        = "evm:db:restore:remote"
        @task_params = [
          "--",
          {
            :uri          => uri,
            :uri_username => user,
            :uri_password => pass
          }
        ]
      end

      def ask_to_delete_backup_after_restore
        if backup_type == LOCAL_FILE
          say("The local database restore file is located at: '#{uri}'.\n")
          @delete_agree = agree("Should this file be deleted after completing the restore? (Y/N): ")
        end
      end

      def confirm_and_execute
        say("\nNote: A database restore cannot be undone.  The restore will use the file: #{uri}.\n")
        if agree("Are you sure you would like to restore the database? (Y/N): ")
          say("\nRestoring the database...")
          rake_success = ManageIQ::ApplianceConsole::Utilities.rake(task, task_params)
          if rake_success && delete_agree
            say("\nRemoving the database restore file #{uri}...")
            File.delete(uri)
          elsif !rake_success
            say("\nDatabase restore failed. Check the logs for more information")
          end
        end
        press_any_key
      end

      def setting_header
        say("#{I18n.t("advanced_settings.dbrestore")}\n\n")
      end
    end
  end
end
