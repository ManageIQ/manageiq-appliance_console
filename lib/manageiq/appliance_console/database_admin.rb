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

      attr_accessor :uri
      attr_reader :action, :backup_type, :task, :task_params, :delete_agree, :filename

      def initialize(action = :restore, input = $stdin, output = $stdout)
        super(input, output)

        @action      = action
        @task_params = []
      end

      def local_backup?
        backup_type == "local".freeze
      end

      def object_store_backup?
        backup_type == "s3".freeze || backup_type == "swift".freeze
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
        ask_to_split_up_output
      end

      def activate
        clear_screen
        setting_header

        ask_to_delete_backup_after_restore
        confirm_and_execute
      end

      def ask_file_location
        @backup_type = ask_with_menu(*file_menu_args) do |menu|
          menu.choice(CANCEL) { |_| raise MiqSignalError }
        end
        if URI(backup_type).scheme
          ask_custom_file_options(backup_type)
        else
          # calling methods like ask_ftp_file_options and ask_s3_file_options
          send("ask_#{backup_type}_file_options")
        end
      end

      def ask_local_file_options
        @uri         = just_ask(*filename_prompt_args)
        @task        = "evm:db:#{action}:local"
        @task_params = ["--", {:local_file => uri}]
      end

      def ask_nfs_file_options
        @filename    = just_ask(*filename_prompt_args) unless action == :restore
        @uri         = ask_for_uri(*remote_file_prompt_args_for("nfs"))
        @task        = "evm:db:#{action}:remote"

        params = {:uri => uri}
        params[:remote_file_name] = filename if filename

        @task_params = ["--", params]
      end

      def ask_smb_file_options
        @filename    = just_ask(*filename_prompt_args) unless action == :restore
        @uri         = ask_for_uri(*remote_file_prompt_args_for("smb"))
        user         = just_ask(USER_PROMPT)
        pass         = ask_for_password("password for #{user}")

        params = {
          :uri          => uri,
          :uri_username => user,
          :uri_password => pass
        }
        params[:remote_file_name] = filename if filename

        @task        = "evm:db:#{action}:remote"
        @task_params = ["--", params]
      end

      def ask_s3_file_options
        access_key_prompt = <<-PROMPT.strip_heredoc.chomp
          Access Key ID with access to this file.
          Example: 'amazon_aws_user'
        PROMPT

        @filename    = just_ask(*filename_prompt_args) unless action == :restore
        @uri         = ask_for_uri(*remote_file_prompt_args_for("s3"), :optional_path => true)
        region       = just_ask("Amazon Region for database file", "us-east-1")
        user         = just_ask(access_key_prompt)
        pass         = ask_for_password("Secret Access Key for #{user}")

        params = {
          :uri          => uri,
          :uri_username => user,
          :uri_password => pass,
          :aws_region   => region
        }
        params[:remote_file_name] = filename if filename

        @task        = "evm:db:#{action}:remote"
        @task_params = ["--", params]
      end

      def ask_ftp_file_options
        @filename    = just_ask(*filename_prompt_args) unless action == :restore
        @uri         = ask_for_uri(*remote_file_prompt_args_for("ftp"), :optional_path => true)
        user         = just_ask(USER_PROMPT)
        pass         = ask_for_password("password for #{user}")

        params = { :uri => uri }
        params[:uri_username]     = user     if user.present?
        params[:uri_password]     = pass     if pass.present?
        params[:remote_file_name] = filename if filename

        @task        = "evm:db:#{action}:remote"
        @task_params = ["--", params]
      end

      def ask_custom_file_options(server_uri)
        hostname  = URI(server_uri).host
        @filename = ask_custom_file_prompt(hostname)
        @uri      = server_uri

        params = {:uri => uri, :remote_file_name => filename}

        if (custom_params = custom_endpoint_config_for(hostname))
          params.merge!(custom_params[:rake_options]) if custom_params[:rake_options]
        end

        @task        = "evm:db:#{action}:remote"
        @task_params = ["--", params]
      end

      def ask_swift_file_options
        require 'uri'
        swift_user_prompt = <<-PROMPT.strip_heredoc.chomp
          User Name with access to this file.
          Example: 'openstack_user'
        PROMPT

        @filename  = just_ask(*filename_prompt_args) { |q| q.readline = false } unless action == :restore
        @uri       = URI(ask_for_uri(*remote_file_prompt_args_for("swift")) { |q| q.readline = false })
        @task      = "evm:db:#{action}:remote"
        user       = just_ask(swift_user_prompt) { |q| q.readline = false }
        pass       = ask_for_password("password for #{user}") { |q| q.readline = false }
        @uri.query = swift_query_elements.join('&').presence

        params = {
          :uri          => @uri.to_s,
          :uri_username => user,
          :uri_password => pass
        }
        params[:remote_file_name] = filename if filename
        @task        = "evm:db:#{action}:remote"
        @task_params = ["--", params]
      end

      def swift_query_elements
        region            = just_ask("OpenStack Swift Region") { |q| q.readline = false }
        @uri.port         = just_ask("OpenStack Swift Port", "5000") { |q| q.readline = false }
        security_protocol = ask_with_menu(*security_protocol_menu_args)
        api_version       = ask_with_menu(*api_version_menu_args) { |q| q.readline = false }
        domain_ident      = just_ask("OpenStack V3 Domain Identifier") { |q| q.readline = false } if api_version == "v3"
        query_elements    = []
        query_elements    << "region=#{region}"                       if region.present?
        query_elements    << "api_version=#{api_version}"             if api_version.present?
        query_elements    << "domain_id=#{domain_ident}"              if domain_ident.present?
        query_elements    << "security_protocol=#{security_protocol}" if security_protocol.present?
      end

      def ask_to_delete_backup_after_restore
        if action == :restore && local_backup?
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
        end || true
      end

      def ask_to_split_up_output
        if action == :dump && should_split_output?
          @task_params.last[:byte_count] = ask_for_string("byte size to split by", "500M")
        end || true
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

      def api_version_menu_args
        [
          "OpenStack API Version",
          [["Keystone v2".freeze, "v2".freeze], ["Keystone v3".freeze, "v3".freeze], ["None".freeze, nil]].freeze,
          ["Keystone v2".freeze, "v2".freeze],
          nil
        ]
      end

      def file_menu_args
        [
          action == :restore ? "Restore Database File Source" : "#{action.capitalize} Output File Destination",
          file_options,
          "local",
          nil
        ]
      end

      def security_protocol_menu_args
        [
          "OpenStack Security Protocol",
          [["SSL without validation".freeze, "ssl".freeze], ["SSL".freeze, "ssl-with-validation".freeze], ["Non-SSL".freeze, "non-ssl".freeze], ["None".freeze, nil]].freeze,
          ["Non-SSL".freeze, "non-ssl".freeze],
          nil
        ]
      end

      def setting_header
        say("#{I18n.t("advanced_settings.db#{action}")}\n\n")
      end

      private

      def ask_custom_file_prompt(hostname)
        prompts = custom_endpoint_config_for(hostname)
        prompt_text  = prompts && prompts[:filename_text] || "Target filename for backup".freeze
        prompt_regex = prompts && prompts[:filename_validator]
        validator    = prompt_regex ? ->(x) { x.to_s =~ /#{prompt_regex}/ } : ->(x) { x.to_s.present? }
        just_ask(prompt_text, nil, validator)
      end

      def skip_file_location?(hostname)
        config = custom_endpoint_config_for(hostname)
        return false unless config && config[:enabled_for].present?
        !Array(config[:enabled_for]).include?(action.to_s)
      end

      def custom_endpoint_config_for(hostname)
        # hostname has a period in it, so we need to look it up by [] instead of the traditional i18n method
        I18n.t("database_admin.prompts", :default => {})[hostname.to_sym]
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
        if object_store_backup?
          prompt  = "name for the remote #{action} file"
          default = File.basename(default)
        end
        [prompt, default, nil, "file that exists"]
      end

      def restore_prompt_args
        default   = DB_RESTORE_FILE
        validator = LOCAL_FILE_VALIDATOR if local_backup?
        prompt    = "location of the local restore file"
        [prompt, default, validator, "file that exists"]
      end

      def remote_file_prompt_args_for(remote_type)
        prompt  = if action == :restore
                    "location of the remote backup file"
                  else
                    "location to save the remote #{action} file to"
                  end
        prompt += "\nExample: #{sample_url(remote_type)}"
        [prompt, remote_type]
      end

      def sample_url(scheme)
        I18n.t("database_admin.sample_url.#{scheme}")
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
