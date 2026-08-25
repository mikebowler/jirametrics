# frozen_string_literal: true

require './spec/spec_helper'

describe MockIssue do
  let(:board) { sample_board }

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

    it 'uses the created date it was given' do
      issue = described_class.empty(board: board, created: '2024-03-04')
      expect(issue.created.to_date.to_s).to eq '2024-03-04'
    end
  end
end
