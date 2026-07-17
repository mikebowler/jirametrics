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

  describe '#cycletime_unit' do
    it 'defaults to days' do
      expect(chart.x_axis_title).to eq 'Cycle time in days'
    end

    it 'reflects :minutes in the axis title' do
      chart.cycletime_unit :minutes
      expect(chart.x_axis_title).to eq 'Cycle time in minutes'
    end

    it 'reflects :hours in the axis title' do
      chart.cycletime_unit :hours
      expect(chart.x_axis_title).to eq 'Cycle time in hours'
    end

    it 'raises for invalid units' do
      expect { chart.cycletime_unit :weeks }.to raise_error(ArgumentError)
    end
  end

  describe '#value_for_item' do
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

  describe '#title_for_item' do
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

  describe '#label_for_item' do
    it 'formats PR number and title' do
      expect(chart.label_for_item(pull_request, hint: nil)).to eq '42 Fix the bug'
    end

    it 'appends hint when provided' do
      expect(chart.label_for_item(pull_request, hint: ' (merged)')).to eq '42 Fix the bug (merged)'
    end
  end
end
