# frozen_string_literal: true

require './spec/spec_helper'

describe AgingWorkBarChart do
  context 'pick_colors_for_statuses' do
    let(:status_story_ready) { Status.new name: 'ready', id: 0, category_name: 'To Do', category_id: 0 }
    let(:status_task_ready)  { Status.new name: 'ready', id: 0, category_name: 'To Do', category_id: 0 }
    let(:status_task_ready_done) { Status.new name: 'ready', id: 0, category_name: 'Done', category_id: 0 }

    it 'should not set colours when no statuses' do
      chart = AgingWorkBarChart.new
      chart.possible_statuses = []
      expect(chart.pick_colors_for_statuses).to be_empty
    end

    it 'should set color for a single status' do
      chart = AgingWorkBarChart.new
      chart.possible_statuses = [
        status_story_ready
      ]
      expect(chart.pick_colors_for_statuses).to eq({
        status_story_ready => '#B0E0E6'
      })
    end

    it 'should assign the same color for two statuses with the same name, in the same category' do
      chart = AgingWorkBarChart.new
      chart.possible_statuses = [
        status_story_ready,
        status_task_ready
      ]
      expect(chart.pick_colors_for_statuses).to eq({
        status_story_ready => '#B0E0E6',
        status_task_ready => '#B0E0E6'
      })
    end

    it 'should assign different colors for two statuses with the same name, but in different categories' do
      chart = AgingWorkBarChart.new
      chart.possible_statuses = [
        status_story_ready,
        status_task_ready,
        status_task_ready_done
      ]
      expect(chart.pick_colors_for_statuses).to eq({
        status_story_ready => '#B0E0E6',
        status_task_ready => '#B0E0E6',
        status_task_ready_done => '#7CFC00'
      })
    end

    it 'should handle the In Progress category' do
      status = Status.new name: 'ready', id: 0, category_name: 'In Progress', category_id: 0
      chart = AgingWorkBarChart.new
      chart.possible_statuses = [status]
      expect(chart.pick_colors_for_statuses).to eq({ status => '#FFEFD5' })
    end

    # Theoretically it's impossible to have any other category but then again, this is Jira.
    it 'should raise exception for unknown status category' do
      status = Status.new name: 'ready', id: 0, category_name: 'Unknown', category_id: 0
      chart = AgingWorkBarChart.new
      chart.possible_statuses = [status]
      expect { chart.pick_colors_for_statuses }.to raise_error 'Unexpected status category: Unknown'
    end
  end
end
