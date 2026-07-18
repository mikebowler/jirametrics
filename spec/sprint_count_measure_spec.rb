# frozen_string_literal: true

require './spec/spec_helper'

describe SprintCountMeasure do
  let(:measure) { described_class.new }

  def change action, key: 'SP-1'
    SprintIssueChangeData.new(
      action: action, time: to_time('2022-01-01'), value: 0.0,
      issue: Struct.new(:key).new(key), estimate: 0.0
    )
  end

  describe '#value' do
    it 'starts at zero' do
      expect(measure.value).to eq 0
    end
  end

  describe '#update_state' do
    it 'counts an entering issue' do
      measure.update_state change(:enter_sprint)
      expect(measure.value).to eq 1
    end

    it 'uncounts a leaving issue' do
      measure.update_state change(:enter_sprint)
      measure.update_state change(:leave_sprint)
      expect(measure.value).to eq 0
    end

    it 'uncounts a completed issue' do
      measure.update_state change(:enter_sprint)
      measure.update_state change(:issue_stopped)
      expect(measure.value).to eq 0
    end
  end

  describe '#record' do
    it 'records and counts an added issue' do
      aggregate_failures do
        expect(measure.record(change(:enter_sprint))).to eq 'Added to sprint'
        expect(measure.summary_stats.added).to eq 1
      end
    end

    it 'records and counts a completed issue' do
      aggregate_failures do
        expect(measure.record(change(:issue_stopped))).to eq 'Completed'
        expect(measure.summary_stats.completed).to eq 1
      end
    end

    it 'records and counts a removed issue' do
      aggregate_failures do
        expect(measure.record(change(:leave_sprint))).to eq 'Removed from sprint'
        expect(measure.summary_stats.removed).to eq 1
      end
    end

    it 'returns nil for an action it does not describe' do
      expect(measure.record(change(:story_points))).to be_nil
    end
  end

  describe 'titles' do
    it 'describes the sprint start, end, and still-active states from the current count' do
      measure.update_state change(:enter_sprint)
      measure.update_state change(:enter_sprint, key: 'SP-2')
      aggregate_failures do
        expect(measure.started_title).to eq 'Sprint started with 2 stories'
        expect(measure.ended_title).to eq 'Sprint ended with 2 stories unfinished'
        expect(measure.active_title).to eq 'Sprint still active. 2 issues in progress.'
      end
    end
  end
end
