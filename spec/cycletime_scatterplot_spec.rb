# frozen_string_literal: true

require './spec/spec_helper'
require './lib/cycletime_scatterplot'

describe CycletimeScatterplot do
  context 'data_for_issue' do
    it '' do
      issue = load_issue('SP-10')
      chart = CycletimeScatterplot.new
      chart.cycletime = defaultCycletimeConfig
      expect(chart.data_for_issue issue).to eq({
        'title' => ['SP-10 : 80 days', 'Check in people at an event'],
        'x' => issue.last_resolution,
        'y' => 80
      })
    end
  end

  context 'label_days' do
    it 'should return singular for 1' do
      chart = CycletimeScatterplot.new
      expect(chart.label_days 1).to eq '1 day'
    end

    it 'should return singular for 0' do
      chart = CycletimeScatterplot.new
      expect(chart.label_days 0).to eq '0 days'
    end
  end

  it 'should create_datasets' do
    issue = load_issue('SP-10')

    chart = CycletimeScatterplot.new
    chart.cycletime = defaultCycletimeConfig
    chart.issues = [issue]
    expect(chart.create_datasets).to eq([
      {
        'backgroundColor' => 'green',
        'data' => [
          {
            'title' => ['SP-10 : 80 days', 'Check in people at an event'],
            'x' => issue.last_resolution,
            'y' => 80
         }
        ],
        'fill' => false,
        'label' => 'Story',
        'showLine' => false
       }
     ])
  end
end
