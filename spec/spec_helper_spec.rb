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

  context 'create_issue_from_aging_data' do
    let(:board) { sample_board }

    it 'creates no issues when no ages' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-30')]
      ]
    end

    it 'creates no issues when all zeros' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [0, 0], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-30')]
      ]
    end

    it 'handles simple data' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [0, 1, 2], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-29')],
        ['In Progress', to_time('2024-10-29')],
        ['Review', to_time('2024-10-29T01:00:00')]
      ]
    end

    it 'handles bigger gaps' do
      issue = create_issue_from_aging_data board: board, ages_by_column: [1, 5, 3], today: '2024-10-30'
      expect(issue.status_changes.collect { |c| [c.value, c.time] }).to eq [
        ['Backlog', to_time('2024-10-24')],
        ['Selected for Development', to_time('2024-10-24')],
        ['In Progress', to_time('2024-10-24T01:00:00')],
        ['Review', to_time('2024-10-28T02:00:00')]
      ]
    end
  end
end
