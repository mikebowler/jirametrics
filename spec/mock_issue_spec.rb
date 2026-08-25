# frozen_string_literal: true

require './spec/spec_helper'

describe MockIssue do
  let(:board) { sample_board }

  # Only the specs for the generator itself care which key comes out. Every other test either
  # passes a key or does not care, so there is deliberately no suite-wide reset: a test that
  # asserted on a generated key would then be flaky, which is how it should find out.
  before { described_class.reset_generated_keys }

  describe '.empty' do
    it 'is a real Issue, so anything taking an Issue will accept it' do
      expect(described_class.empty(board: board)).to be_a Issue
    end

    # A defaulted key was the trap: several issues sharing one key silently share one cycletime
    # stub, because MockCycleTimeConfig matches stubs by key.
    it 'generates a key when none is given' do
      expect(described_class.empty(board: board).key).to eq 'SP-1000'
    end

    it 'generates a different key for each issue' do
      keys = Array.new(3) { described_class.empty(board: board).key }
      expect(keys).to eq %w[SP-1000 SP-1001 SP-1002]
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

  # Random ordering means a process-global counter would make keys depend on how many issues
  # earlier examples built, so the same test would see different keys on different seeds.
  describe '.reset_generated_keys' do
    it 'starts again from the first key' do
      described_class.empty board: board
      described_class.reset_generated_keys
      expect(described_class.empty(board: board).key).to eq 'SP-1000'
    end
  end
end
