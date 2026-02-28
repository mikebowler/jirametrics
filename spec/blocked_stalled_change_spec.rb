# frozen_string_literal: true

require './spec/spec_helper'

describe BlockedStalledChange do
  context 'reasons' do
    it 'stalled by inactivity' do
      change = described_class.new time: '2022-01-01', stalled_days: 5
      expect(change.reasons).to eq 'Stalled by inactivity: 5 days'
    end

    it 'stalled by status' do
      change = described_class.new(
        time: '2022-01-01', stalled_days: 5, status: 'Stalled', status_is_blocking: false
      )
      expect(change.reasons).to eq 'Stalled by status: Stalled'
    end

    it 'blocked by status' do
      change = described_class.new(
        time: '2022-01-01', stalled_days: 5, status: 'Blocked', status_is_blocking: true
      )
      expect(change.reasons).to eq 'Blocked by status: Blocked'
    end

    it 'handles not blocked or stalled' do
      change = described_class.new time: '2022-01-01'
      expect(change.reasons).to eq ''
    end

    it 'correctly handles flagged with stalled by status' do
      change = described_class.new(
        time: '2022-01-01', flagged: true, status: 'Stalled', status_is_blocking: false
      )
      expect(change.reasons).to eq 'Blocked by flag'
    end

    it 'blocked by flag without flag_reason' do
      change = described_class.new(time: '2022-01-01', flagged: true)
      expect(change.reasons).to eq 'Blocked by flag'
    end

    it 'blocked by flag with flag_reason' do
      change = described_class.new(time: '2022-01-01', flagged: true, flag_reason: 'Waiting on vendor')
      expect(change.reasons).to eq 'Blocked by flag: Waiting on vendor'
    end
  end

  context 'inspect' do
    it 'is active' do
      change = described_class.new(time: '2022-01-01')
      expect(change.inspect).to eq "BlockedStalledChange(time: '2022-01-01', Active)"
    end

    it 'is blocked by flag' do
      change = described_class.new(time: '2022-01-01', flagged: true)
      expect(change.inspect).to eq "BlockedStalledChange(time: '2022-01-01', Blocked by flag)"
    end
  end

  context 'flag_reason' do
    it 'stores the flag reason when provided' do
      change = described_class.new(time: '2022-01-01', flagged: true, flag_reason: 'Waiting on vendor')
      expect(change.flag_reason).to eq 'Waiting on vendor'
    end

    it 'is nil when not provided' do
      change = described_class.new(time: '2022-01-01', flagged: true)
      expect(change.flag_reason).to be_nil
    end
  end
end
