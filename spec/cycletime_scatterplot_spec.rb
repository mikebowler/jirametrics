# frozen_string_literal: true

require './spec/spec_helper'
require './lib/cycletime_scatterplot'

describe CycletimeScatterplot do
  let(:chart) { CycletimeScatterplot.new }

  context 'data_for_issue' do
    it '' do
      issue = load_issue('SP-10')
      chart.cycletime = default_cycletime_config
      expect(chart.data_for_issue issue).to eq({
        'title' => ['SP-10 : Check in people at an event (81 days)'],
        'x' => chart_format(issue.last_resolution),
        'y' => 81
      })
    end
  end

  context 'label_days' do
    it 'should return singular for 1' do
      expect(chart.label_days 1).to eq '1 day'
    end

    it 'should return singular for 0' do
      expect(chart.label_days 0).to eq '0 days'
    end
  end

  it 'should create_datasets' do
    issue = load_issue('SP-10')

    chart.cycletime = default_cycletime_config
    chart.issues = [issue]

    expect(chart.create_datasets [issue]).to eq([
      {
        'backgroundColor' => 'green',
        'data' => [
          {
            'title' => ['SP-10 : Check in people at an event (81 days)'],
            'x' => chart_format(issue.last_resolution),
            'y' => 81
         }
        ],
        'fill' => false,
        'label' => 'Story (85% at 81 days)',
        'showLine' => false
       }
     ])
  end

  context 'group_issues' do
    let(:issue1) { load_issue 'SP-1' }

    it 'should render when no rules specified' do
      expected_rules = CycletimeScatterplot::GroupingRules.new
      expected_rules.color = 'green'
      expected_rules.label = issue1.type
      expect(chart.group_issues([issue1])).to eq({
        expected_rules => [issue1]
      })
    end
  end
end
