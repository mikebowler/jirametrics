# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
class Exporter
  def standard_project name:, file_prefix:, ignore_issues: nil, starting_status: nil, boards: {},
      default_board: nil, anonymize: false, settings: {}, status_category_mappings: {},
      rolling_date_count: 90, no_earlier_than: nil, ignore_types: %w[Sub-task Subtask Epic],
      show_experimental_charts: false

    project name: name do
      puts name
      file_prefix file_prefix

      self.anonymize if anonymize
      self.settings.merge! settings

      status_category_mappings.each do |status, category|
        status_category_mapping status: status, category: category
      end

      download do
        self.rolling_date_count(rolling_date_count) if rolling_date_count
        self.no_earlier_than(no_earlier_than) if no_earlier_than
      end

      boards.each_key do |board_id|
        block = boards[board_id]
        if block == :default
          block = lambda do |_|
            start_at first_time_in_status_category(:indeterminate)
            stop_at still_in_status_category(:done)
          end
        end
        board id: board_id do
          cycletime(&block)
        end
      end

      issues.reject! do |issue|
        ignore_types.include? issue.type
      end

      discard_changes_before status_becomes: (starting_status || :backlog) # rubocop:disable Style/RedundantParentheses

      file do
        file_suffix '.html'

        issues.reject! { |issue| ignore_issues.include? issue.key } if ignore_issues

        html_report do
          board_id default_board if default_board

          html "<H1>#{name}</H1>", type: :header
          boards.each_key do |id|
            board = find_board id
            html "<div><a href='#{board.url}'>#{id} #{board.name}</a> (#{board.board_type})</div>",
                 type: :header
          end
          cycletime_scatterplot do
            grouping_rules do |issue, rules|
              rules.label = issue.raw['fields']['priority']['name']
            end
          end
          cycletime_scatterplot do
            grouping_rules do |issue, rules|
              expedited = issue.changes.any? do |change|
                change.priority? &&
                  issue.board.project_config.settings['expedited_priority_names'].include?(change.value)
              end
              if expedited
                rules.label = 'Expedited'
                rules.color = 'red'
              else
                rules.label = 'Standard'
                rules.color = 'gray'
              end
            end
          end

          cycletime_scatterplot do
            show_trend_lines
          end
          cycletime_histogram

          throughput_chart do
            description_text '<h2>Number of items completed, grouped by issue type</h2>'
          end
          throughput_chart do
            header_text nil
            description_text '<h2>Number of items completed, grouped by completion status and resolution</h2>'
            grouping_rules do |issue, rules|
              if issue.resolution
                rules.label = "#{issue.status.name}:#{issue.resolution}"
              else
                rules.label = issue.status.name
              end
            end
          end

          aging_work_in_progress_chart
          aging_work_bar_chart
          aging_work_table
          daily_wip_by_age_chart
          daily_wip_by_blocked_stalled_chart
          daily_wip_by_parent_chart
          flow_efficiency_scatterplot if show_experimental_charts
          expedited_chart
          sprint_burndown
          estimate_accuracy_chart
          dependency_chart
        end
      end
    end
  end
end
