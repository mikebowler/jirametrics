# frozen_string_literal: true

require './spec/spec_helper'

describe PullRequestCycleTimeHistogram do
  let(:chart) { described_class.new(empty_config_block) }

  let(:pull_request) do
    PullRequest.new(raw: {
      'title' => 'Fix the bug',
      'repo' => 'my-repo',
      'number' => 42,
      'opened_at' => '2024-01-01T00:00:00Z',
      'closed_at' => '2024-01-03T12:00:00Z' # 2.5 days = 60 hours = 3600 minutes
    })
  end

  context 'cycletime_unit' do
    it 'defaults to :days' do
      expect(chart.instance_variable_get(:@cycletime_unit)).to eq :days
    end

    it 'defaults x_axis_title to days' do
      expect(chart.x_axis_title).to eq 'Cycle time in days'
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

    it 'updates x_axis_title when unit changes' do
      chart.cycletime_unit :hours
      expect(chart.x_axis_title).to eq 'Cycle time in hours'
    end

    it 'raises for invalid units' do
      expect { chart.cycletime_unit :weeks }.to raise_error(ArgumentError)
    end
  end

  context 'value_for_item' do
    it 'returns days by default (ceiling)' do
      expect(chart.value_for_item(pull_request)).to eq 3
    end

    it 'returns hours when unit is :hours (ceiling)' do
      chart.cycletime_unit :hours
      expect(chart.value_for_item(pull_request)).to eq 60
    end

    it 'returns minutes when unit is :minutes (ceiling)' do
      chart.cycletime_unit :minutes
      expect(chart.value_for_item(pull_request)).to eq 3600
    end
  end

  context 'title_for_item' do
    it 'uses days by default' do
      expect(chart.title_for_item(count: 2, value: 3)).to eq '2 PRs closed in 3 days'
    end

    it 'uses singular PR when count is 1' do
      expect(chart.title_for_item(count: 1, value: 3)).to eq '1 PR closed in 3 days'
    end

    it 'uses hours when unit is :hours' do
      chart.cycletime_unit :hours
      expect(chart.title_for_item(count: 2, value: 60)).to eq '2 PRs closed in 60 hours'
    end

    it 'uses minutes when unit is :minutes' do
      chart.cycletime_unit :minutes
      expect(chart.title_for_item(count: 2, value: 3600)).to eq '2 PRs closed in 3600 minutes'
    end
  end

  context 'label_for_item' do
    it 'formats PR number and title' do
      expect(chart.label_for_item(pull_request, hint: nil)).to eq '42 Fix the bug'
    end

    it 'appends hint when provided' do
      expect(chart.label_for_item(pull_request, hint: ' (merged)')).to eq '42 Fix the bug (merged)'
    end
  end
end
