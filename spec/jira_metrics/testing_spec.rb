# frozen_string_literal: true

require './spec/spec_helper'

describe JiraMetrics::Testing do
  describe '.to_time' do
    it 'parses date only' do
      expect(to_time('2024-01-01').inspect).to eq '2024-01-01 00:00:00 +0000'
    end

    it 'parses date/time' do
      expect(to_time('2024-01-01T12:34:56').inspect).to eq '2024-01-01 12:34:56 +0000'
    end

    it 'parses date/time with fractional seconds' do
      expect(to_time('2024-01-01T12:34:56.789').inspect).to eq '2024-01-01 12:34:56.789 +0000'
    end

    it 'parses date/time with fractional seconds and offset' do
      expect(to_time('2024-01-01T12:34:56.789+10:00').inspect).to eq '2024-01-01 12:34:56.789 +1000'
    end

    it 'parses date/time with offset' do
      expect(to_time('2024-01-01T12:34:56 +10:00').inspect).to eq '2024-01-01 12:34:56 +1000'
    end

    it 'passes a Time straight through, so a caller can mix Times and strings' do
      time = Time.now
      expect(to_time(time)).to be time
    end

    it 'names the string it could not parse rather than failing somewhere later' do
      expect { to_time('last Tuesday') }.to raise_error(/Can't parse string: "last Tuesday"/)
    end
  end

  describe '.to_date' do
    it 'parses a date string' do
      expect(to_date('2024-01-01')).to eq Date.new(2024, 1, 1)
    end

    it 'passes a Date straight through, matching to_time' do
      date = Date.new(2024, 1, 1)
      expect(to_date(date)).to be date
    end
  end

  describe '.empty_config_block' do
    # Charts instance_eval the block they're given, so "empty" has to mean both accepted and
    # inert. Asserting the chart's own default header survived covers the second half: a block
    # that configured anything would have had the chance to overwrite it.
    it 'satisfies a chart that requires a configuration block, and configures nothing' do
      chart = ThroughputChart.new empty_config_block
      expect(chart.header_text).to eq 'Throughput Chart'
    end
  end

  # These two are the supported surface, and the whole of it. Adding to either list is a decision to
  # freeze that signature, since exposed means deprecation on change, so they exist to force the
  # decision rather than let something arrive unnoticed. Four mocks became public exactly that way.
  #
  # Failing here is not a bug. It means something was added or removed and nobody said which.
  describe 'the supported surface' do
    it 'is exactly these classes' do
      expect(described_class.constants).to match_array %i[
        MockBoard MockChangeItem MockCycleTimeConfig MockIssue
      ]
    end

    it 'is exactly these methods' do
      expect(described_class.public_instance_methods(false)).to match_array %i[
        empty_config_block to_date to_time
      ]
    end
  end
end
