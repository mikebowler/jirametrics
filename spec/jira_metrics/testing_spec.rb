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
end
