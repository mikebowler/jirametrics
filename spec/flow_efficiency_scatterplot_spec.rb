# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/cycletime_scatterplot'

describe FlowEfficiencyScatterplot do
  let(:settings) do
    {
      'blocked_statuses' => StatusCollection.new,
      'stalled_statuses' => StatusCollection.new,
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

  describe '#run' do
    # description_text is expanded at render time, so a reference in it to something that has been
    # removed stays invisible until a report is generated. Running the chart for real catches it.
    it 'renders the description' do
      issue = MockIssue.empty created: '2020-01-01', board: sample_board
      issue.board.cycletime = mock_cycletime_config stub_values: [[issue, '2020-01-02', '2020-01-20']]
      settings['stalled_threshold_days'] = 50

      chart.file_system.when_loading(
        file: File.expand_path('./lib/jirametrics/html/flow_efficiency_scatterplot.erb'), json: :not_mocked
      )
      chart.all_boards = { issue.board.id => issue.board }
      chart.issues = [issue]
      chart.date_range = to_date('2020-01-01')..to_date('2020-02-01')
      chart.holiday_dates = []

      expect(chart.run).to include 'the active time against the'
    end
  end

  describe '#create_dataset' do
    it 'returns nil when no issues' do
      expect(chart.create_dataset issues: [], label: 'label', color: 'color').to be_nil
    end

    it 'handles one issue' do
      issue = MockIssue.empty created: '2020-01-01', board: sample_board, key: 'SP-1'
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
      issue = MockIssue.empty created: '2020-01-01', board: sample_board, key: 'SP-1'
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
