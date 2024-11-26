require 'resolv'
require 'io/console'

module ManageIQ
module ApplianceConsole
  CANCEL = 'Cancel'.freeze

  module Prompts
    CLEAR_CODE    = `clear`
    IPV4_REGEXP   = Resolv::IPv4::Regex
    IPV6_REGEXP   = Resolv::IPv6::Regex
    IP_REGEXP     = Regexp.union(Resolv::IPv4::Regex, Resolv::IPv6::Regex).freeze
    DOMAIN_REGEXP = /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*(\.[a-z]{2,13})?$/
    INT_REGEXP    = /^[0-9]+$/
    NONE_REGEXP   = /^('?NONE'?)?$/i.freeze
    HOSTNAME_REGEXP = /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/.freeze
    MESSAGING_HOSTNAME_REGEXP = /^(?!.*localhost)(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/.freeze
    MESSAGING_PASSWORD_REGEXP = /\A[a-zA-Z0-9_\-\.\$\*]+\z/.freeze

    def ask_for_uri(prompt, expected_scheme, opts = {})
      require 'uri'
      just_ask(prompt, nil, nil, 'a valid URI') do |q|
        q.validate = lambda do |a|
          # Convert all backslashes in the URI to forward slashes and strip whitespace
          a.tr!('\\', '/')
          a.strip!
          u = URI(a)
          # validate it has a hostname/ip and a share
          u.scheme == expected_scheme &&
            (u.host =~ HOSTNAME_REGEXP || u.hostname =~ IP_REGEXP) &&
            (opts[:optional_path] || !u.path.empty?)
        end
        yield q if block_given?
      end
    end

    def press_any_key
      say("\nPress any key to continue.")
      HighLine.default_instance.tap do |highline|
        highline.terminal.raw_no_echo_mode_exec do
          highline.terminal.get_character
        end
      end
    end

    def clear_screen
      print CLEAR_CODE
    end

    def are_you_sure?(clarifier = nil)
      clarifier = " you want to #{clarifier}" if clarifier && !clarifier.include?("want")
      agree("Are you sure#{clarifier}? (Y/N): ")
    end

    def ask_yn?(prompt, default = nil)
      ask("#{prompt}? (Y/N): ") do |q|
        q.default = default if default
        q.validate = ->(p) { (p.blank? && default) || %w(y n).include?(p.downcase[0]) }
        q.responses[:not_valid] = "Please provide yes or no."
        yield q if block_given?
      end.downcase[0] == 'y'
    end

    def ask_for_domain(prompt, default = nil, validate = DOMAIN_REGEXP, error_text = "a valid Domain.", &block)
      just_ask(prompt, default, validate, error_text, &block)
    end

    def ask_for_ip(prompt, default, validate = IP_REGEXP, error_text = "a valid IP Address.", &block)
      just_ask(prompt, default, validate, error_text, &block)
    end

    def ask_for_hostname(prompt, default = nil, validate = HOSTNAME_REGEXP, error_text = "a valid Hostname.", &block)
      just_ask(prompt, default, validate, error_text, &block)
    end

    def ask_for_messaging_hostname(prompt, default = nil, error_text = "a valid Messaging Hostname (not an IP or localhost)", &block)
      validation = ->(h) { h =~ MESSAGING_HOSTNAME_REGEXP && h !~ IP_REGEXP }
      just_ask(prompt, default, validation, error_text, &block)
    end

    def ask_for_ip_or_hostname(prompt, default = nil)
      validation = ->(h) { (h =~ HOSTNAME_REGEXP || h =~ IP_REGEXP) && h.length > 0 }
      ask_for_ip(prompt, default, validation, "a valid Hostname or IP Address.")
    end

    def ask_for_ip_or_hostname_or_none(prompt, default = nil)
      validation = Regexp.union(NONE_REGEXP, HOSTNAME_REGEXP, IP_REGEXP)
      ask_for_ip(prompt, default, validation, "a valid Hostname or IP Address.").gsub(NONE_REGEXP, "")
    end

    def ask_for_schedule_frequency(prompt, default = nil)
      validation = ->(h) { %w(hourly daily weekly monthly).include?(h) }
      just_ask(prompt, default, validation, "hourly, daily, weekly or monthly")
    end

    def ask_for_hour_number(prompt)
      ask_for_integer(prompt, (0..23))
    end

    def ask_for_week_day_number(prompt)
      ask_for_integer(prompt, (0..6))
    end

    def ask_for_month_day_number(prompt)
      ask_for_integer(prompt, (1..31))
    end

    def ask_for_many(prompt, collective = nil, default = nil, max_length = 255, max_count = 6)
      collective ||= "#{prompt}s"
      validate = ->(p) { (p.length < max_length) && (p.split(/[\s,;]+/).length <= max_count) }
      error_message = "up to #{max_count} #{prompt}s separated by a space and up to #{max_length} characters"
      just_ask(collective, default, validate, error_message).split(/[\s,;]+/).collect(&:strip)
    end

    def ask_for_password(prompt, default = nil)
      pass = just_ask(prompt, default.present? ? "********" : nil) do |q|
        q.echo = '*'
        yield q if block_given?
      end
      pass == "********" ? (default || "") : pass
    end

    def ask_for_new_password(prompt, default: nil, allow_empty: false, retry_limit: 1, confirm_password: true, validation: nil, validation_err: nil)
      count = 0
      loop do
        password1 = ask_for_password(prompt, default)
        if password1.strip.empty? && !allow_empty
          say("\nPassword can not be empty, please try again")
          next
        end

        if validation && password1 !~ validation
          say("\nPassword is invalid: #{validation_err}, please try again")
          next
        end

        return password1 if password1 == default || !confirm_password

        password2 = ask_for_password(prompt)
        return password1 if password1 == password2

        raise "passwords did not match" if count >= retry_limit

        count += 1
        say("\nThe passwords did not match, please try again")
      end
    end

    def ask_for_messaging_password(prompt)
      ask_for_new_password(prompt, :validation => MESSAGING_PASSWORD_REGEXP, :validation_err => "allowed characters are a-z, A-Z, 0-9, -, _, ., $, and *")
    end

    def ask_for_string(prompt, default = nil)
      just_ask(prompt, default)
    end

    def ask_for_integer(prompt, range = nil, default = nil)
      just_ask(prompt, default, INT_REGEXP, "an integer", Integer) { |q| q.in = range if range }
    end

    def ask_for_disk(disk_name, verify = true, silent = false)
      require "linux_admin"
      disks = LinuxAdmin::Disk.local.select { |d| d.partitions.empty? }

      if disks.empty?
        say("No partition found for #{disk_name}. You probably want to add an unpartitioned disk and try again.") unless silent
      else
        default_choice = disks.size == 1 ? "1" : nil
        disk = ask_with_menu(
          disk_name,
          disks.collect { |d| [("#{d.path}: #{d.size.to_i / 1.megabyte} MB"), d] },
          default_choice
        ) do |q|
          q.choice("Don't partition the disk") { nil }
        end
      end
      if verify && disk.nil?
        say("")
        raise MiqSignalError unless are_you_sure?(" you don't want to partition the #{disk_name}")
      end
      disk
    end

    # use the integer index for menu prompts
    # ensure default is a string
    def default_to_index(default, options)
      return unless default
      default_index = if options.kind_of?(Hash)
                        options.values.index(default) || options.keys.index(default)
                      else
                        options.index(default)
                      end
      default_index ? (default_index.to_i + 1).to_s : default.to_s
    end

    def ask_with_menu(prompt, options, default = nil, clear_screen_after = true)
      say("#{prompt}\n\n")

      default = default_to_index(default, options)
      selection = nil
      choose do |menu|
        menu.default      = default
        menu.index        = :number
        menu.index_suffix = ") "
        menu.prompt       = "\nChoose the #{prompt.downcase}:#{" |#{default}|" if default} "
        options.each { |o, v| menu.choice(o) { |c| selection = v || c } }
        yield menu if block_given?
      end
      clear_screen if clear_screen_after
      selection
    end

    def just_ask(prompt, default = nil, validate = nil, error_text = nil, klass = nil)
      ask("Enter the #{prompt}: ", klass) do |q|
        q.default = default.to_s if default
        q.validate = validate if validate
        q.responses[:not_valid] = error_text ? "Please provide #{error_text}" : "Please provide in the specified format"
        yield q if block_given?
      end
    end
  end
end
end
