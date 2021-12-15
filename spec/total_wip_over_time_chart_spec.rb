# frozen_string_literal: true

require './spec/spec_helper'

def newTotalWipOverTimeChart
  chart = TotalWipOverTimeChart.new
  block = lambda do |_|
    start_at created
    stop_at last_resolution
  end
  chart.cycletime = CycleTimeConfig.new parent_config: nil, label: nil, block: block
  chart
end

describe TotalWipOverTimeChart do
  context 'make_start_stop_sequence_for_issues' do
    it 'should handle no issues' do
      chart = TotalWipOverTimeChart.new
      chart.issues = []
      expect(chart.make_start_stop_sequence_for_issues).to be_empty
    end

    it 'should handle one issue that is done' do
      chart = newTotalWipOverTimeChart
      issue = load_issue 'SP-10'
      chart.issues = [issue]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue.created, 'start', issue],
        [issue.last_resolution, 'stop', issue]
      ]
    end

    it 'should handle one issue that isn\'t done' do
      chart = newTotalWipOverTimeChart
      issue = load_issue 'SP-1'
      chart.issues = [issue]
      expect(chart.make_start_stop_sequence_for_issues).to eq [
        [issue.created, 'start', issue]
      ]
    end
  end
end
