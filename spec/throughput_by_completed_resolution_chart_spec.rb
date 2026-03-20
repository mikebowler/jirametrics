# frozen_string_literal: true

require './spec/spec_helper'
require 'jirametrics/throughput_by_completed_resolution_chart'

describe ThroughputByCompletedResolutionChart do
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue 'SP-1', board: board }

  it 'sets a descriptive header_text' do
    chart = described_class.new empty_config_block
    expect(chart.header_text).to eq 'Throughput, grouped by completion status and resolution'
  end

  it 'sets description_text' do
    chart = described_class.new empty_config_block
    expect(chart.description_text).to include('grouped by completion status and resolution')
  end

  context 'default_grouping_rules' do
    let(:done_status) do
      Status.new(name: 'Done', id: 10_002, category_name: 'Done', category_id: 3, category_key: 'done')
    end

    it 'sets label and label_hint from status and resolution when resolution present' do
      allow(issue1).to receive(:status_resolution_at_done).and_return([done_status, 'Fixed'])
      chart = described_class.new empty_config_block

      rules = GroupingRules.new
      chart.default_grouping_rules(issue1, rules)

      expect(rules.label).to eq 'Done:Fixed'
      expect(rules.label_hint).to include('Done')
      expect(rules.label_hint).to include('Fixed')
    end

    it 'sets label and label_hint from status only when no resolution' do
      allow(issue1).to receive(:status_resolution_at_done).and_return([done_status, nil])
      chart = described_class.new empty_config_block

      rules = GroupingRules.new
      chart.default_grouping_rules(issue1, rules)

      expect(rules.label).to eq 'Done'
      expect(rules.label_hint).to include('Done')
      expect(rules.label_hint).not_to include('resolution')
    end
  end

  it 'allows grouping_rules to be overridden via block' do
    chart = described_class.new(proc do
      grouping_rules do |_issue, rules|
        rules.label = 'custom'
      end
    end)

    rules = GroupingRules.new
    chart.instance_variable_get(:@group_by_block).call(issue1, rules)
    expect(rules.label).to eq 'custom'
  end
end
