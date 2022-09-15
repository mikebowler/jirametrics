# frozen_string_literal: true

require './spec/spec_helper'

describe DailyWipChart do
  let(:subject) do
    empty_config_block = ->(_) {}
    chart = DailyWipChart.new empty_config_block
    chart.date_range = Date.parse('2022-01-01')..Date.parse('2022-04-02')
    chart
  end

  context 'group_issues_by_active_dates' do
    it 'should return nothing when no issues' do
      subject.issues = []
      expect(subject.group_issues_by_active_dates).to be_empty
    end

    it 'should return raise exception when no grouping rules set' do
      issue1 = load_issue('SP-1')
      subject.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      subject.issues = [issue1]
      expect { subject.group_issues_by_active_dates }.to raise_error('grouping_rules must be set')
    end

    it 'should return nothing when grouping rules ignore everything' do
      issue1 = load_issue('SP-1')
      subject.cycletime = mock_cycletime_config stub_values: [
        [issue1, to_time('2022-02-02T11:00:00'), to_time('2022-02-02T14:00:00')]
      ]
      subject.issues = [issue1]
      subject.grouping_rules do |_issue, rules|
        rules.ignore
      end
      expect(subject.group_issues_by_active_dates).to be_empty
    end
  end
end
