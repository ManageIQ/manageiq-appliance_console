require 'active_support/core_ext/string/strip'
require 'optimist'

class OptimistEducateSpecError < StandardError; end
class OptimistDieSpecError < StandardError; end

RSpec.configure do |config|
  config.before(:each) do
    err_string = <<-EOF.strip_heredoc
      Don't allow methods that exit the calling process to be executed in specs.
      If you were testing that we call Optimist.educate or Optimist.die, expect that a OptimistEducateSpecError or OptimistDieSpecError be raised instead
    EOF
    allow(Optimist).to receive(:educate).and_raise(OptimistEducateSpecError.new(err_string))
    allow(Optimist).to receive(:die).and_raise(OptimistDieSpecError.new(err_string))
  end
end
