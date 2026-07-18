# frozen_string_literal: true

require './spec/spec_helper'

describe SprintPointsMeasure do
  let(:measure) { described_class.new }

  def change action, key: 'SP-1', value: 0.0, estimate: 0.0
    SprintIssueChangeData.new(
      action: action, time: to_time('2022-01-01'), value: value,
      issue: Struct.new(:key).new(key), estimate: estimate
    )
  end

  describe '#value' do
    it 'starts at zero' do
      expect(measure.value).to eq 0.0
    end
  end

  describe '#update_state' do
    it 'adds an entering issue estimate' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      expect(measure.value).to eq 5.0
    end

    it 'subtracts a leaving issue estimate' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      measure.update_state change(:leave_sprint, estimate: 3.0)
      expect(measure.value).to eq 2.0
    end

    it 'applies a story point change for an issue in the sprint' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      measure.update_state change(:story_points, value: 3.0)
      expect(measure.value).to eq 8.0
    end

    it 'ignores a story point change for an issue not in the sprint' do
      measure.update_state change(:story_points, key: 'SP-2', value: 3.0)
      expect(measure.value).to eq 0.0
    end

    it 'stops applying story point changes after an issue leaves the sprint' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      measure.update_state change(:leave_sprint, estimate: 5.0)
      measure.update_state change(:story_points, value: 3.0)
      expect(measure.value).to eq 0.0
    end
  end

  describe '#record' do
    it 'records and counts an entering issue' do
      aggregate_failures do
        expect(measure.record(change(:enter_sprint, estimate: 5.0))).to eq 'Added to sprint with 5.0 points'
        expect(measure.summary_stats.added).to eq 5.0
      end
    end

    it 'records a completed issue and decrements the estimate' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      aggregate_failures do
        expect(measure.record(change(:issue_stopped, estimate: 5.0))).to eq 'Completed with 5.0 points'
        expect(measure.summary_stats.completed).to eq 5.0
        expect(measure.value).to eq 0.0
      end
    end

    it 'records a removed issue' do
      aggregate_failures do
        expect(measure.record(change(:leave_sprint, estimate: 5.0))).to eq 'Removed from sprint with 5.0 points'
        expect(measure.summary_stats.removed).to eq 5.0
      end
    end

    it 'records a story point change for an issue in the sprint' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      aggregate_failures do
        expect(measure.record(change(:story_points, value: 3.0, estimate: 8.0)))
          .to eq 'Story points changed from 5.0 points to 8.0 points'
        expect(measure.summary_stats.points_values_changed).to be true
      end
    end

    it 'ignores a story point change for an issue not in the sprint' do
      aggregate_failures do
        expect(measure.record(change(:story_points, key: 'SP-2', value: 3.0, estimate: 8.0))).to be_nil
        expect(measure.summary_stats.points_values_changed).to be false
      end
    end

    it 'stops applying story point changes after an issue completes' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      measure.record change(:issue_stopped, estimate: 5.0)
      measure.update_state change(:story_points, value: 3.0)
      expect(measure.value).to eq 0.0
    end

    it 'raises on an unexpected action' do
      expect { measure.record change(:banana) }.to raise_error 'Unexpected action: banana'
    end
  end

  describe 'titles' do
    it 'describes the sprint start, end, and still-active states from the current estimate' do
      measure.update_state change(:enter_sprint, estimate: 5.0)
      aggregate_failures do
        expect(measure.started_title).to eq 'Sprint started with 5.0 points'
        expect(measure.ended_title).to eq 'Sprint ended with 5.0 points unfinished'
        expect(measure.active_title).to eq 'Sprint still active. 5.0 points still in progress.'
      end
    end
  end
end
