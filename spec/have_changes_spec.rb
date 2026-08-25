# frozen_string_literal: true

require './spec/spec_helper'

describe HaveChanges do
  let(:board) { sample_board }
  let(:issue) { MockIssue.empty board: board }

  before do
    issue.add_change field: 'status', value: 'In Progress', value_id: 3, time: '2024-03-01'
    issue.add_change field: 'priority', value: 'High', old_value: 'Low', time: '2024-03-02'
  end

  # The first two are the artificial changes every issue gets from its creation.
  it 'matches when every declared attribute agrees' do
    expect(issue).to have_changes [
      { field: 'status', value: 'Backlog', artificial: true },
      { field: 'priority', value: 'Medium', artificial: true },
      { field: 'status', value: 'In Progress', value_id: 3, time: '2024-03-01' },
      { field: 'priority', value: 'High', old_value: 'Low', time: '2024-03-02' }
    ]
  end

  it 'ignores attributes the expectation does not mention' do
    expect(issue).to have_changes [
      { field: 'status' }, { field: 'priority' }, { field: 'status' }, { field: 'priority' }
    ]
  end

  # ChangeItem#== only compares field, value and time, so an array of ChangeItems compared with eq
  # silently ignores a wrong id. This matcher is the reason to prefer it.
  # Some subjects expose a filtered subset, like Issue#status_changes, so the matcher takes either
  # an issue or the changes themselves.
  it 'accepts a collection of changes rather than an issue' do
    expect(issue.changes.select(&:status?)).to have_changes [
      { field: 'status', value: 'Backlog', artificial: true },
      { field: 'status', value: 'In Progress', value_id: 3 }
    ]
  end

  it 'notices a value_id that does not agree' do
    matcher = described_class.new [
      { field: 'status' }, { field: 'priority' },
      { field: 'status', value: 'In Progress', value_id: 99 },
      { field: 'priority' }
    ]
    aggregate_failures do
      expect(matcher.matches?(issue)).to be false
      expect(matcher.failure_message).to include 'value_id'
    end
  end

  it 'notices the wrong number of changes' do
    matcher = described_class.new [{ field: 'status' }]
    aggregate_failures do
      expect(matcher.matches?(issue)).to be false
      expect(matcher.failure_message).to match(/number/i)
    end
  end

  it 'says which change differed' do
    matcher = described_class.new [
      { field: 'status' }, { field: 'resolution' }, { field: 'status' }, { field: 'priority' }
    ]
    matcher.matches? issue
    expect(matcher.failure_message).to include 'Change 2'
  end
end
