require 'manageiq/appliance_console/errors'

module ManageIQ
  module ApplianceConsole
    class DatabaseAdmin < HighLine
      include ManageIQ::ApplianceConsole::Prompts

      LOCAL_FILE     = "Local file".freeze
      NFS_FILE       = "Network File System (NFS)".freeze
      SMB_FILE       = "Samba (SMB)".freeze
      CANCEL         = "Cancel".freeze
      FILE_OPTIONS   = [LOCAL_FILE, NFS_FILE, SMB_FILE, CANCEL].freeze

      DB_RESTORE_FILE      = "/tmp/evm_db.backup".freeze
      LOCAL_FILE_VALIDATOR = ->(a) { File.exist?(a) }.freeze

      USER_PROMPT = <<-PROMPT.strip_heredoc.chomp
        username with access to this file.
        Example: 'mydomain.com/user'
      PROMPT

      DB_DUMP_WARNING = <<-WARN.strip_heredoc
        WARNING:  This is not the recommended and supported way of running a
        database backup, and is strictly meant for exporting a database for
        support/debugging purposes!


      WARN

      attr_reader :action, :backup_type, :task, :task_params, :delete_agree, :uri

      def initialize(action = :restore, input = $stdin, output = $stdout)
        super(input, output)

        @action      = action
        @task_params = []
      end

      def ask_questions
        setting_header
        say(DB_DUMP_WARNING) if action == :dump
        ask_file_location
        ask_for_tables_to_exclude_in_dump
      end

      def activate
        clear_screen
        setting_header

        ask_to_delete_backup_after_restore
        confirm_and_execute
      end

      def ask_file_location
        case @backup_type = ask_with_menu(*file_menu_args)
        when LOCAL_FILE then ask_local_file_options
        when NFS_FILE   then ask_nfs_file_options
        when SMB_FILE   then ask_smb_file_options
        when CANCEL     then raise MiqSignalError
        end
      end

      def ask_local_file_options
        @uri = just_ask(local_file_prompt,
                        DB_RESTORE_FILE, LOCAL_FILE_VALIDATOR,
                        "file that exists")

        @task        = "evm:db:#{action}:local"
        @task_params = ["--", {:local_file => uri}]
      end

      def ask_nfs_file_options
        @uri         = ask_for_uri(*remote_file_prompt_args_for("nfs"))
        @task        = "evm:db:#{action}:remote"
        @task_params = ["--", {:uri => uri}]
      end

      def ask_smb_file_options
        @uri         = ask_for_uri(*remote_file_prompt_args_for("smb"))
        user         = just_ask(USER_PROMPT)
        pass         = ask_for_password("password for #{user}")

        @task        = "evm:db:#{action}:remote"
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
        if action == :restore && backup_type == LOCAL_FILE
          say("The local database restore file is located at: '#{uri}'.\n")
          @delete_agree = agree("Should this file be deleted after completing the restore? (Y/N): ")
        end
      end

      def ask_for_tables_to_exclude_in_dump
        if action == :dump && should_exclude_tables?
          say(<<-PROMPT.strip_heredoc)

            To exclude tables from the dump, enter them in a space separated
            list.  For example:

                > metrics_* vim_performance_states event_streams

          PROMPT
          table_excludes = ask_for_many("table",
                                        "tables to exclude",
                                        "metrics_* vim_performance_states event_streams",
                                        255,
                                        Float::INFINITY)

          @task_params.last[:"exclude-table-data"] = table_excludes
        end
      end

      def confirm_and_execute
        if allowed_to_execute?
          processing_message
          run_rake
        end
        press_any_key
      end

      def allowed_to_execute?
        return true unless action == :restore
        say("\nNote: A database restore cannot be undone.  The restore will use the file: #{uri}.\n")
        agree("Are you sure you would like to restore the database? (Y/N): ")
      end

      def file_menu_args
        [
          action == :restore ? "Restore Database File" : "#{action.capitalize} Output File Name",
          FILE_OPTIONS,
          LOCAL_FILE,
          nil
        ]
      end

      def setting_header
        say("#{I18n.t("advanced_settings.db#{action}")}\n\n")
      end

      private

      def should_exclude_tables?
        ask_yn?("Would you like to exclude tables in the dump") do |q|
          q.readline = true
        end
      end

      def local_file_prompt
        if action == :restore
          "location of the local restore file"
        else
          "location to save the #{action} file to"
        end
      end

      def remote_file_prompt_args_for(remote_type)
        prompt  = if action == :restore
                    "location of the remote backup file"
                  else
                    "location to save the remote #{action} file to"
                  end
        prompt += "\nExample: #{SAMPLE_URLS[remote_type]}"
        [prompt, remote_type]
      end

      def processing_message
        msg = if action == :restore
                "\nRestoring the database..."
              else
                "\nRunning Database #{action} to #{uri}..."
              end
        say(msg)
      end

      def run_rake
        rake_success = ManageIQ::ApplianceConsole::Utilities.rake(task, task_params)
        if rake_success && action == :restore && delete_agree
          say("\nRemoving the database restore file #{uri}...")
          File.delete(uri)
        elsif !rake_success
          say("\nDatabase #{action} failed. Check the logs for more information")
        end
      end
    end
  end
end
