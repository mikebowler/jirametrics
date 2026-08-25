# frozen_string_literal: true

require './spec/spec_helper'

describe MockCycleTimeConfig do
  let(:board) { sample_board }

  # Stubs are matched by the issue's key, so two stubs carrying the same key can only ever mean a
  # mistake: one of them is unreachable and the test would assert against a fixture that says
  # something other than what it appears to say.
  describe 'duplicate keys' do
    it 'raises when two stubs share a key' do
      first = MockIssue.empty board: board, key: 'SP-9'
      second = MockIssue.empty board: board, key: 'SP-9'

      expect { described_class.new stub_values: [[first, '2024-01-01', nil], [second, '2024-06-01', nil]] }
        .to raise_error(/SP-9/)
    end

    it 'allows distinct keys' do
      first = MockIssue.empty board: board, key: 'SP-1'
      second = MockIssue.empty board: board, key: 'SP-2'

      expect { described_class.new stub_values: [[first, '2024-01-01', nil], [second, '2024-06-01', nil]] }
        .not_to raise_error
    end
  end

  # The caller's array used to be normalized in place, so holding one in a let or reusing it across
  # two configs handed you something different the second time.
  it 'leaves the array it was given untouched' do
    issue = MockIssue.empty board: board, key: 'SP-1'
    stubs = [[issue, '2024-01-01', '2024-02-01']]

    described_class.new stub_values: stubs

    expect(stubs).to eq [[issue, '2024-01-01', '2024-02-01']]
  end

  it 'still resolves the times it was given' do
    issue = MockIssue.empty board: board, key: 'SP-1'
    config = described_class.new stub_values: [[issue, '2024-01-01', '2024-02-01']]

    expect(config.started_stopped_times(issue).collect { |time| time&.strftime('%Y-%m-%d') })
      .to eq %w[2024-01-01 2024-02-01]
  end
end
