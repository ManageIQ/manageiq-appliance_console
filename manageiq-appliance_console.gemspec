# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'manageiq/appliance_console/version'

Gem::Specification.new do |spec|
  spec.name          = "manageiq-appliance_console"
  spec.version       = ManageIQ::ApplianceConsole::VERSION
  spec.authors       = ["ManageIQ Developers"]

  spec.summary       = "ManageIQ Appliance Console"
  spec.description   = "ManageIQ Appliance Console"
  spec.homepage      = "https://github.com/ManageIQ/manageiq-appliance_console"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "activerecord",            "~> 5.0.7.1"
  spec.add_runtime_dependency "activesupport",           "~> 5.0.7.1"
  spec.add_runtime_dependency "awesome_spawn",           "~> 1.4"
  spec.add_runtime_dependency "bcrypt",                  "~> 3.1.10"
  spec.add_runtime_dependency "highline",                "~> 1.6.21"
  spec.add_runtime_dependency "linux_admin",             ["~> 1.0", ">=1.2.2"]
  spec.add_runtime_dependency "optimist",                "~> 3.0"
  spec.add_runtime_dependency "pg"
  spec.add_runtime_dependency "rails-i18n",              "~> 5.x"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "codeclimate-test-reporter", "~> 1.0.0"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"
end
