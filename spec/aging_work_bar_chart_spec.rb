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
  end

  context 'data_set_by_block' do
    let(:subject) { AgingWorkBarChart.new }

    it 'should handle nothing blocked at all' do
      issue = load_issue('SP-1')
      data_sets = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| false }

      expect(data_sets).to be_nil
    end

    it 'should handle a single blocked range completely within the date range' do
      issue = load_issue('SP-1')
      data_sets = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..6).include? day.day }

      expect(data_sets).to eq(
        {
          backgroundColor: 'red',
          data: [
            {
              title: 'Story : Blocked 4 days',
              x: %w[2022-01-03 2022-01-06],
              y: 'SP-1'
            }
          ],
          stack: 'blocked',
          stacked: true,
          type: 'bar'
        }
      )
    end

    it 'should handle multiple blocked ranges, all completely within the date range' do
      issue = load_issue('SP-1')
      data_set = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |day| (3..4).include?(day.day) || day.day == 6 }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set[:data]).to eq([
        {
          title: 'Story : Blocked 2 days',
          x: %w[2022-01-03 2022-01-04],
          y: 'SP-1'
        },
        {
          title: 'Story : Blocked 1 day',
          x: %w[2022-01-06 2022-01-06],
          y: 'SP-1'
        }
      ])
    end

    it 'never becomes unblocked' do
      issue = load_issue('SP-1')
      data_set = subject.data_set_by_block(
        issue: issue, issue_label: issue.key, title_label: 'Blocked', stack: 'blocked',
        color: 'red', start_date: to_date('2022-01-01'), end_date: to_date('2022-01-10')
      ) { |_day| true }

      # Only checking the data section as the full wrapper was tested above.
      expect(data_set[:data]).to eq([
        {
          title: 'Story : Still Blocked',
          x: %w[2022-01-01 2022-01-10],
          y: 'SP-1'
        }
      ])
    end
  end
end
