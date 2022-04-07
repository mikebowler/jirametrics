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
    it 'should raise exception if board cannot be determined' do
      subject.all_board_columns = {}
      expect { subject.board_columns }.to raise_error 'Couldn\'t find any board configurations. Ensure one is set'
    end

    it 'should return correct columns when board id set' do
      columns1 = []
      subject.board_id = 1
      subject.all_board_columns = { 1 => columns1 }
      expect(subject.board_columns).to be columns1
    end

    it 'should return correct columns when board id not set but only one board in use' do
      columns1 = []
      subject.all_board_columns = { 1 => columns1 }
      expect(subject.board_columns).to be columns1
    end

    it 'should raise exception when board id not set and multiple boards in use' do
      columns1 = [1]
      columns2 = [2]
      subject.all_board_columns = { 1 => columns1, 2 => columns2 }
      expect { subject.board_columns }.to raise_error(
        'Must set board_id so we know which to use. Multiple boards found: [1, 2]'
      )
    end
  end
end
