# frozen_string_literal: true

require './spec/spec_helper'

describe PullRequestCycleTimeScatterplot do
  let(:chart) { described_class.new(empty_config_block) }

  let(:pull_request) do
    PullRequest.new(raw: {
      'title' => 'Fix the bug',
      'repo' => 'my-repo',
      'opened_at' => '2024-01-01T00:00:00Z',
      'closed_at' => '2024-01-03T12:00:00Z' # 2.5 days = 60 hours = 3600 minutes
    })
  end

  let(:rules) do
    GroupingRules.new.tap { |r| r.label = 'my-repo' }
  end

  context 'cycletime_unit' do
    it 'defaults to :days' do
      expect(chart.instance_variable_get(:@cycletime_unit)).to eq :days
    end

    it 'defaults y_axis_title to days' do
      expect(chart.y_axis_title).to eq 'Cycle time in days'
    end

    it 'updates y_axis_title when unit changes' do
      chart.cycletime_unit :hours
      expect(chart.y_axis_title).to eq 'Cycle time in hours'
    end

    it 'accepts :minutes' do
      chart.cycletime_unit :minutes
      expect(chart.instance_variable_get(:@cycletime_unit)).to eq :minutes
    end

    it 'accepts :hours' do
      chart.cycletime_unit :hours
      expect(chart.instance_variable_get(:@cycletime_unit)).to eq :hours
    end

    it 'accepts :days' do
      chart.cycletime_unit :days
      expect(chart.instance_variable_get(:@cycletime_unit)).to eq :days
    end

    it 'raises for invalid units' do
      expect { chart.cycletime_unit :weeks }.to raise_error(ArgumentError)
    end
  end

  context 'y_value' do
    it 'returns days by default' do
      expect(chart.y_value(pull_request)).to eq 3
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

  context 'label_cycletime' do
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

  context 'title_value' do
    it 'uses days by default' do
      expect(chart.title_value(pull_request, rules: rules)).to eq 'Fix the bug | my-repo | Age:3 days'
    end

    it 'uses hours when unit is :hours' do
      chart.cycletime_unit :hours
      expect(chart.title_value(pull_request, rules: rules)).to eq 'Fix the bug | my-repo | Age:60 hours'
    end

    it 'uses minutes when unit is :minutes' do
      chart.cycletime_unit :minutes
      expect(chart.title_value(pull_request, rules: rules)).to eq 'Fix the bug | my-repo | Age:3600 minutes'
    end
  end
end
