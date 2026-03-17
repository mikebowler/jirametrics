# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
class Exporter
  def standard_project name:, file_prefix:, ignore_issues: nil, starting_status: nil, boards: {},
      default_board: nil, anonymize: false, settings: {}, status_category_mappings: {},
      rolling_date_count: 90, no_earlier_than: nil, ignore_types: %w[Sub-task Subtask Epic],
      show_experimental_charts: false, github_repos: nil
    exporter = self
    project name: name do
      puts name
      file_prefix file_prefix

      self.anonymize if anonymize
      self.settings.merge! stringify_keys(settings)

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

      status_category_mappings.each do |status, category|
        status_category_mapping status: status, category: category
      end

      download do
        self.rolling_date_count(rolling_date_count) if rolling_date_count
        self.no_earlier_than(no_earlier_than) if no_earlier_than
        github_repo github_repos if github_repos
      end

      issues.reject! do |issue|
        ignore_types.include? issue.type
      end

      exporter.filter_issues issues, ignore_issues

      discard_changes_before status_becomes: (starting_status || :backlog) # rubocop:disable Style/RedundantParentheses

      file do
        file_suffix '.html'

        html_report do
          board_id default_board if default_board

          html "<H1>#{name}</H1>", type: :header
          boards.each_key do |id|
            board = find_board id
            html "<div><a href='#{board.url}'>#{id} #{board.name}</a> (#{board.board_type})</div>",
                 type: :header
          end

          daily_view

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
              status, resolution = issue.status_resolution_at_done
              if resolution
                rules.label = "#{status.name}:#{resolution}"
              else
                rules.label = status.name
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
          sprint_burndown
          estimate_accuracy_chart
          dependency_chart
        end
      end
    end
  end

  # Extracted as a separate method so it can be tested independently, without needing to invoke
  # the full standard_project DSL setup.
  def filter_issues issues, ignore_issues
    return unless ignore_issues

    issues.reject! do |issue|
      ignore_issues.is_a?(Proc) ? ignore_issues.call(issue) : ignore_issues.include?(issue.key)
    end
  end
end
