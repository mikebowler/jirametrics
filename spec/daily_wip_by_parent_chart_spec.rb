# frozen_string_literal: true

require './spec/spec_helper'

describe DailyWipByParentChart do
  let(:chart) do
    chart = described_class.new nil
    chart.date_range = to_date('2022-01-01')..to_date('2022-02-01')
    chart.time_range = to_time('2022-01-01')..to_time('2022-02-01T23:59:59')
    chart
  end
  let(:board) { load_complete_sample_board }
  let(:issue1) { load_issue('SP-1', board: board).tap { |i| i.changes.clear } }
  let(:issue2) { load_issue('SP-2', board: board).tap { |i| i.changes.clear } }

  it 'compiles and runs text with embedded erb' do
    expect(chart.default_header_text).not_to be_nil
    expect(chart.default_description_text).not_to be_nil
  end

  context 'grouping_rules' do
    it 'detects no parent' do
      rules = DailyGroupingRules.new
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.label).to eq 'No parent'
    end

    it 'detects parent' do
      issue1.parent = issue2
      rules = DailyGroupingRules.new
      chart.default_grouping_rules issue: issue1, rules: rules
      expect(rules.label).to eq 'SP-2'
    end
  end
end
