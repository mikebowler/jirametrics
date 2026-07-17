# frozen_string_literal: true

require './spec/spec_helper'

describe PullRequestCycleTimeScatterplot do
  let(:chart) { described_class.new(empty_config_block) }

  let(:pull_request) do
    PullRequest.new(raw: {
      'title' => 'Fix the bug',
      'repo' => 'my-repo',
      'issue_keys' => ['SP-42'],
      'opened_at' => '2024-01-01T00:00:00Z',
      'closed_at' => '2024-01-03T12:00:00Z' # 2.5 days = 60 hours = 3600 minutes
    })
  end

  let(:rules) do
    GroupingRules.new.tap { |r| r.label = 'my-repo' }
  end

  describe '#cycletime_unit' do
    it 'defaults to days' do
      expect(chart.y_axis_title).to eq 'Cycle time in days'
    end

    it 'reflects :minutes in the axis title' do
      chart.cycletime_unit :minutes
      expect(chart.y_axis_title).to eq 'Cycle time in minutes'
    end

    it 'reflects :hours in the axis title' do
      chart.cycletime_unit :hours
      expect(chart.y_axis_title).to eq 'Cycle time in hours'
    end

    it 'raises for invalid units' do
      expect { chart.cycletime_unit :weeks }.to raise_error(ArgumentError)
    end
  end

  describe '#y_value' do
    before { chart.timezone_offset = '+00:00' }

    it 'returns days by default' do
      expect(chart.y_value(pull_request)).to eq 3
    end

    it 'counts same-day open and close as 1 day' do
      pr = PullRequest.new(raw: {
        'opened_at' => '2024-01-01T09:00:00Z',
        'closed_at' => '2024-01-01T09:00:09Z'
      })
      expect(chart.y_value(pr)).to eq 1
    end

    it 'returns hours when unit is :hours' do
      chart.cycletime_unit :hours
      expect(chart.y_value(pull_request)).to eq 60
    end

    it 'returns minutes when unit is :minutes' do
      chart.cycletime_unit :minutes
      expect(chart.y_value(pull_request)).to eq 3600
    end
  end

  describe '#label_cycletime' do
    it 'labels days singular' do
      expect(chart.label_cycletime(1)).to eq '1 day'
    end

    it 'labels days plural' do
      expect(chart.label_cycletime(3)).to eq '3 days'
    end

    it 'labels hours' do
      chart.cycletime_unit :hours
      expect(chart.label_cycletime(60)).to eq '60 hours'
    end

    it 'labels minutes' do
      chart.cycletime_unit :minutes
      expect(chart.label_cycletime(3600)).to eq '3600 minutes'
    end

    it 'labels 1 minute as singular' do
      chart.cycletime_unit :minutes
      expect(chart.label_cycletime(1)).to eq '1 minute'
    end
  end

  describe '#title_value' do
    it 'uses days by default' do
      expect(chart.title_value(pull_request, rules: rules)).to eq 'SP-42 | Fix the bug | my-repo | Age:3 days'
    end

    it 'uses hours when unit is :hours' do
      chart.cycletime_unit :hours
      expect(chart.title_value(pull_request, rules: rules)).to eq 'SP-42 | Fix the bug | my-repo | Age:60 hours'
    end

    it 'uses minutes when unit is :minutes' do
      chart.cycletime_unit :minutes
      expect(chart.title_value(pull_request, rules: rules)).to eq 'SP-42 | Fix the bug | my-repo | Age:3600 minutes'
    end
  end
end
