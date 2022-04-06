# frozen_string_literal: true

require './spec/spec_helper'

describe ChartBase do
  let(:subject) { ChartBase.new }

  context 'label_days' do
    it 'should be singular for one' do
      expect(subject.label_days(1)).to eq '1 day'
    end

    it 'should be singular for one' do
      expect(subject.label_days(5)).to eq '5 days'
    end
  end

  context 'daily_chart_dataset' do
    let(:issue1) { load_issue('SP-1') }

    it 'should hande the simple positive case' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = subject.daily_chart_dataset(
        date_issues_list: date_issues_list, color: 'red', label: 'MyChart', positive: true
      )

      expect(dataset).to eq({
        type: 'bar',
        label: 'MyChart',
        data: [
          {
            title: ['MyChart (1 issue)', 'SP-1 : Create new draft event'],
            x: Date.parse('2021-10-10'),
            y: 1
          }
        ],
        backgroundColor: 'red',
        borderRadius: 0
      })
    end

    it 'should hande the positive case with a block' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = subject.daily_chart_dataset(
        date_issues_list: date_issues_list, color: 'red', label: 'MyChart', positive: true
      ) { |_date, _issue| '(dynamic content!)'}

      expect(dataset).to eq({
        type: 'bar',
        label: 'MyChart',
        data: [
          {
            title: ['MyChart (1 issue)', 'SP-1 : Create new draft event (dynamic content!)'],
            x: Date.parse('2021-10-10'),
            y: 1
          }
        ],
        backgroundColor: 'red',
        borderRadius: 0
      })
    end

    it 'should hande the simple negative case' do
      date_issues_list = [
        [Date.parse('2021-10-10'), [issue1]]
      ]
      dataset = subject.daily_chart_dataset(
        date_issues_list: date_issues_list, color: 'red', label: 'MyChart', positive: false
      )

      expect(dataset).to eq({
        type: 'bar',
        label: 'MyChart',
        data: [
          {
            title: ['MyChart (1 issue)', 'SP-1 : Create new draft event'],
            x: Date.parse('2021-10-10'),
            y: -1
          }
        ],
        backgroundColor: 'red',
        borderRadius: 5
      })
    end
  end

  context 'board_columns' do
  end
end
