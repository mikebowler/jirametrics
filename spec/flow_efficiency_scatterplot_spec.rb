# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cycletime_scatterplot'

describe FlowEfficiencyScatterplot do
  let(:settings) do
    {
      'blocked_statuses' => %w[Blocked Blocked2],
      'stalled_statuses' => %w[Stalled Stalled2],
      'blocked_link_text' => ['is blocked by'],
      'stalled_threshold_days' => 5,
      'flagged_means_blocked' => true
    }
  end
  let(:chart) do
    described_class.new(empty_config_block).tap do |chart|
      chart.time_range = to_time('2020-01-01')..to_time('2020-02-01')
      chart.settings = settings
      chart.file_system = MockFileSystem.new
    end
  end

  context 'create_dataset' do
    it 'returns nil when no issues' do
      expect(chart.create_dataset issues: [], label: 'label', color: 'color').to be_nil
    end

    it 'handles one issue' do
      issue = empty_issue created: '2020-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, issue.created, nil]
      ]
      settings['stalled_threshold_days'] = 50 # effectively turn off the stalled check.

      expect(chart.create_dataset issues: [issue], label: 'label', color: 'color').to eq({
        backgroundColor: 'color',
        data: [
          {
            title: ['SP-1 : Do the thing, flow efficiency: 100%, total: 31.0 days, active: 31.0 days'],
            x: 31.0,
            y: 31.0
          }
        ],
        fill: false,
        label: 'label',
        showLine: false
      })
    end

    it 'handles case where total time is zero' do
      # Shouldn't be possible with a well configured board but we've seen it in production.
      issue = empty_issue created: '2020-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config stub_values: [
        [issue, issue.created, issue.created]
      ]
      expect(chart.create_dataset issues: [issue], label: 'label', color: 'color').to eq({
        backgroundColor: 'color',
        data: [
          {
            title: ['SP-1 : Do the thing, flow efficiency: 0%, total: 0.0 days, active: 0.0 days'],
            x: 0.0,
            y: 0.0
          }
        ],
        fill: false,
        label: 'label',
        showLine: false
      })
      expect(chart.file_system.log_messages).to eq([
        'Issue(SP-1) flow_efficiency: NaN, active_time: 0.0, total_time: 0.0'
      ])
    end
  end
end
