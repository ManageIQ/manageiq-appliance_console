require 'manageiq/appliance_console/errors'
require 'uri'

module ManageIQ
  module ApplianceConsole
    class DatabaseAdmin < HighLine
      include ManageIQ::ApplianceConsole::Prompts

      DB_RESTORE_FILE      = "/tmp/evm_db.backup".freeze
      DB_DEFAULT_DUMP_FILE = "/tmp/evm_db.dump".freeze
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

      attr_reader :action, :backup_type, :database_opts, :delete_agree, :filename

      def initialize(action = :restore, input = $stdin, output = $stdout)
        super(input, output)

        @action        = action
        @database_opts = {:dbname => DatabaseConfiguration.database_name}
      end

      def uri
        @database_opts[:local_file]
      end

      def ask_questions
        setting_header
        if action == :restore && LinuxAdmin::Service.new("evmserverd").running?
          say("\nDatabase restore failed. Please execute the \“Stop EVM Server Processes\” command and try again.")
          press_any_key
          raise MiqSignalError
        end
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
        @database_opts[:local_file] = just_ask(*filename_prompt_args)
      end

      def ask_to_delete_backup_after_restore
        if action == :restore
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

          @database_opts[:exclude_table_data] = table_excludes
        end || true
      end

      def confirm_and_execute
        if allowed_to_execute?
          processing_message
          run_action
        end
        press_any_key
      end

      def allowed_to_execute?
        return true unless action == :restore

        say("\nNote: A database restore cannot be undone.  The restore will use the file: #{uri}.\n")
        agree("Are you sure you would like to restore the database? (Y/N): ")
      end

      def file_options
        @file_options ||= I18n.t("database_admin.menu_order").each_with_object({}) do |file_option, h|
          # special anonymous ftp sites are defined by uri
          uri = URI(file_option)
          if uri.scheme
            h["#{uri.scheme} to #{uri.host}"] = file_option unless skip_file_location?(uri.host)
          else
            h[I18n.t("database_admin.#{file_option}")] = file_option
          end
        end
      end

      def setting_header
        say("#{I18n.t("advanced_settings.db#{action}")}\n\n")
      end

      private

      def skip_file_location?(hostname)
        config = custom_endpoint_config_for(hostname)
        return false unless config && config[:enabled_for].present?
        !Array(config[:enabled_for]).include?(action.to_s)
      end

      def should_exclude_tables?
        ask_yn?("Would you like to exclude tables in the dump") do |q|
          q.readline = true
        end
      end

      def should_split_output?
        ask_yn?("Would you like to split the #{action} output into multiple parts") do |q|
          q.readline = true
        end
      end

      def filename_prompt_args
        return restore_prompt_args if action == :restore
        default = action == :dump ? DB_DEFAULT_DUMP_FILE : DB_RESTORE_FILE
        prompt  = "location to save the #{action} file to"
        [prompt, default, nil, "file that exists"]
      end

      def restore_prompt_args
        default   = DB_RESTORE_FILE
        validator = LOCAL_FILE_VALIDATOR
        prompt    = "location of the local restore file"
        [prompt, default, validator, "file that exists"]
      end

      def remote_file_prompt_args_for(remote_type)
        prompt  = if action == :restore
                    "location of the remote backup file"
                  else
                    "location to save the remote #{action} file to"
                  end
        prompt += "\nExample: #{sample_url}"
        [prompt, remote_type]
      end

      def sample_url
        I18n.t("database_admin.sample_url.nfs")
      end

      def processing_message
        msg = if action == :restore
                "\nRestoring the database..."
              else
                "\nRunning Database #{action} to #{uri}..."
              end
        say(msg)
      end

      def run_action
        success = send(action)
        if success && action == :restore && delete_agree
          say("\nRemoving the database restore file #{uri}...")
          File.delete(uri)
        elsif !success
          say("\nDatabase #{action} failed. Check the logs for more information")
        end
      end

      def backup
        result = PostgresAdmin.backup(database_opts)
        ManageIQ::ApplianceConsole.logger.info("[#{@database_opts[:dbname]}] database has been backed up to file: [#{uri}]")
        result
      end

      def dump
        result = PostgresAdmin.backup_pg_dump(database_opts)
        ManageIQ::ApplianceConsole.logger.info("[#{@database_opts[:dbname]}] database has been dumped up to file: [#{uri}]")
        result
      end

      def restore
        result = PostgresAdmin.restore(database_opts.merge(:backup_type => backup_type))
        ManageIQ::ApplianceConsole.logger.info("[#{@database_opts[:dbname]}] database has been restored from file: [#{uri}]")
        result
      end
    end
  end
end
