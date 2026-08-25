# frozen_string_literal: true

require './spec/spec_helper'

describe MockIssue do
  let(:board) { sample_board }

  describe '#add_change' do
    # ....add_change() took the issue as an argument, so nothing tied a change to the
    # issue it belonged to except the caller's care. On the mock itself that cannot go wrong.
    it 'appends the change to the issue' do
      issue = described_class.empty board: board
      issue.add_change field: 'status', value: 'In Progress', value_id: 3, time: '2024-03-01'
      expect(issue.changes.collect(&:value)).to include 'In Progress'
    end

    it 'returns the change, for tests that need to hold on to it' do
      issue = described_class.empty board: board
      change = issue.add_change field: 'status', value: 'In Progress', value_id: 3, time: '2024-03-01'
      expect(change.value).to eq 'In Progress'
    end
  end

  describe '.empty' do
    it 'is a real Issue, so anything taking an Issue will accept it' do
      expect(described_class.empty(board: board)).to be_a Issue
    end

    # A defaulted key was the trap: several issues sharing one key silently share one cycletime
    # stub, because MockCycleTimeConfig matches stubs by key. Uniqueness is the whole requirement,
    # so these assert that and not which particular key came out.
    it 'generates a key when none is given' do
      expect(described_class.empty(board: board).key).to match(/\ASP-\d+\z/)
    end

    it 'generates a different key for each issue' do
      keys = Array.new(3) { described_class.empty(board: board).key }
      expect(keys.uniq.size).to eq 3
    end

    # The literal is deliberate. Comparing against the constant would just restate the
    # implementation and pass no matter what the constant became.
    it 'generates keys clear of the hand-written ones that fixtures use' do
      number = described_class.empty(board: board).key.delete_prefix('SP-').to_i
      expect(number).to be >= 1000
    end

    it 'uses the key it was given' do
      expect(described_class.empty(board: board, key: 'ABC-42').key).to eq 'ABC-42'
    end

    it 'does not require a created date, for the many tests that do not care' do
      expect(described_class.empty(board: board).created).not_to be_nil
    end

    # Only two keys of that custom field are ever read: id, and boardId which exists solely so
    # Issue#sprint_field_id can recognise which custom field is the sprint one. Names and states
    # written there before were never read and could contradict the board's own Sprint objects.
    it 'records sprint membership in the custom field Jira uses' do
      issue = described_class.empty board: board, current_sprint_ids: [10, 11]
      expect(issue.raw['fields']['customfield_10020']).to eq [
        { 'id' => 10, 'boardId' => board.id },
        { 'id' => 11, 'boardId' => board.id }
      ]
    end

    # The status block used to hardcode a To Do category whatever status was asked for, so an issue
    # could claim to be Done while sitting in To Do. Everything now comes from the Status itself.
    it 'takes the whole status, category included, from the Status it is given' do
      status = board.possible_statuses.find_all_by_name('Done').first
      issue = described_class.empty board: board, creation_status: status
      expect(issue.raw['fields']['status']).to eq(
        'name' => status.name,
        'id' => status.id.to_s,
        'statusCategory' => {
          'name' => status.category.name, 'id' => status.category.id, 'key' => status.category.key
        }
      )
    end

    it 'uses the created date it was given' do
      issue = described_class.empty(board: board, created: '2024-03-04')
      expect(issue.created.to_date.to_s).to eq '2024-03-04'
    end
  end
end
