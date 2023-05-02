require "readline"

# It would be nice if we didn't need to fetch the world to get
# ManageIQ::ApplianceConsole::RAILS_ROOT
require 'manageiq/appliance_console'
require "manageiq/appliance_console/i18n"

shared_context 'with a terminal ui', :with_ui do
  let(:input) do
    @temp_stdin = Tempfile.new("temp_stdin")
    File.open(@temp_stdin.path, 'w+')
  end

  # this is now data typed in our tests by us via 'say'
  let(:readline_output) do
    @temp_stdout = Tempfile.new("temp_stdout")
    File.open(@temp_stdout.path, 'w+')
  end

  let(:output) { StringIO.new }
  let(:prompt) { "\n?  " }

  before do
    HighLine.default_instance = HighLine.new(input, output)
    Readline.input = input
    Readline.output = readline_output
  end

  after do
    @temp_stdin.close! if @temp_stdin
    @temp_stdout.close! if @temp_stdout
    HighLine.default_instance = HighLine.new
    Readline.input = nil
    Readline.output = nil
  end

  # net/ssh messes with track_eof
  # we need it for testing
  # set it back after we are done
  before do
    @old_track, HighLine.track_eof = HighLine.track_eof?, true
  end

  after do
    HighLine.track_eof = @old_track
  end

  private

  def say(strs)
    Array(strs).each do |str|
      input << str << "\n"
    end
    input.rewind
  end

  def expect_cls
    expect(subject).to receive(:print)
  end

  def expect_output(strs)
    strs = strs.collect { |s| s == "" ? "\n" : s }.join if strs.kind_of?(Array)
    expect(output.string).to eq(strs)
  end

  def expect_heard(strs, check_eof = true)
    strs = Array(strs)
    expect_output(strs)
    expect { subject.ask("is there more") }.to raise_error(EOFError) if check_eof
    expect(input).to be_eof
  end
end
