# frozen_string_literal: true

require './spec/spec_helper'

describe MockCycleTimeConfig do
  let(:board) { sample_board }

  describe '#stub' do
    let(:issue1) { MockIssue.empty board: board, key: 'SP-1' }
    let(:issue2) { MockIssue.empty board: board, key: 'SP-2' }

    it 'records the times against the issue' do
      config = described_class.new.stub(issue1, started: '2021-01-02', stopped: '2021-10-04')

      expect(config.started_stopped_times(issue1).collect { |time| time&.strftime('%Y-%m-%d') })
        .to eq %w[2021-01-02 2021-10-04]
    end

    it 'returns self so calls cascade' do
      config = described_class.new
        .stub(issue1, started: '2021-01-02')
        .stub(issue2, started: '2021-03-04', stopped: '2021-05-06')

      expect(
        [issue1, issue2].collect { |issue| config.started_stopped_times(issue).first&.strftime('%Y-%m-%d') }
      ).to eq %w[2021-01-02 2021-03-04]
    end

    it 'treats an omitted stopped as still in progress' do
      config = described_class.new.stub(issue1, started: '2021-01-02')

      expect(config.started_stopped_times(issue1).last).to be_nil
    end

    it 'treats an issue with no times at all as never started' do
      config = described_class.new.stub(issue1)

      expect(config.started_stopped_times(issue1)).to eq [nil, nil]
    end

    it 'raises on the second stub for the same key, naming the line that did it' do
      duplicate = MockIssue.empty board: board, key: 'SP-1'

      expect { described_class.new.stub(issue1, started: '2021-01-02').stub(duplicate, started: '2021-06-01') }
        .to raise_error(/SP-1/)
    end
  end
end
