source 'https://rubygems.org'

# Specify your gem's dependencies in manageiq-appliance_console.gemspec
gemspec

minimum_version =
  case ENV['TEST_RAILS_VERSION']
  when "7.0"
    "~>7.0.8"
  else
    "~>6.1.4"
  end

gem "activerecord", minimum_version
gem "activesupport", minimum_version
