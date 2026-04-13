# frozen_string_literal: true

require './spec/spec_helper'

describe JiraMetrics do
  let(:logfile) { StringIO.new }
  let(:file_system) do
    FileSystem.new.tap { |fs| fs.logfile = logfile }
  end

  context 'log_uncaught_exception' do
    it 'does nothing when exception is nil' do
      described_class.log_uncaught_exception nil, file_system: file_system
      expect(logfile.string).to be_empty
    end

    it 'does nothing for SystemExit' do
      described_class.log_uncaught_exception SystemExit.new, file_system: file_system
      expect(logfile.string).to be_empty
    end

    it 'does nothing when logfile is $stdout' do
      file_system.logfile = $stdout
      exception = RuntimeError.new('boom')
      exception.set_backtrace(%w[line1 line2])
      described_class.log_uncaught_exception exception, file_system: file_system
      expect(logfile.string).to be_empty
    end

    it 'writes the exception class, message, and backtrace to the logfile' do
      exception = RuntimeError.new('something went wrong')
      exception.set_backtrace(['lib/foo.rb:10:in method_a', 'lib/bar.rb:20:in method_b'])

      described_class.log_uncaught_exception exception, file_system: file_system

      output = logfile.string
      expect(output).to include('RuntimeError: something went wrong')
      expect(output).to include("\tlib/foo.rb:10:in method_a")
      expect(output).to include("\tlib/bar.rb:20:in method_b")
    end
  end
end
