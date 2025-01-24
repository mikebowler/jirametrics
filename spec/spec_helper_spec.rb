# frozen_string_literal: true

require './spec/spec_helper'

describe 'spec_helper' do
  context 'to_time' do
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
  end
end
