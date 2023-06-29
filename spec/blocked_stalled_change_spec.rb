# frozen_string_literal: true

require './spec/spec_helper'

describe BlockedStalledChange do
  context 'reasons' do
    it 'stalled by inactivity' do
      change = BlockedStalledChange.new time: '2022-01-01', stalled_days: 5
      expect(change.reasons).to eq 'Stalled by inactivity: 5 days'
    end

    it 'stalled by status' do
      change = BlockedStalledChange.new(
        time: '2022-01-01', stalled_days: 5, status: 'Stalled', status_is_blocking: false
      )
      expect(change.reasons).to eq 'Stalled by status: Stalled'
    end

    it 'blocked by status' do
      change = BlockedStalledChange.new(
        time: '2022-01-01', stalled_days: 5, status: 'Blocked', status_is_blocking: true
      )
      expect(change.reasons).to eq 'Blocked by status: Blocked'
    end

    it 'should handle not blocked or stalled' do
      change = BlockedStalledChange.new time: '2022-01-01'
      expect(change.reasons).to eq ''
    end

    it 'should correctly handle flagged with stalled by status' do
      change = BlockedStalledChange.new(
        time: '2022-01-01', flagged: true, status: 'Stalled', status_is_blocking: false
      )
      expect(change.reasons).to eq 'Blocked by flag'
    end
  end
end
