# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
#
# See https://github.com/mikebowler/jirametrics/wiki/Examples-folder for more
class Exporter
  def standard_project name:, file_prefix:, ignore_issues: nil, starting_status: nil, boards: {},
      default_board: nil, anonymize: false, settings: {}, status_category_mappings: {},
      rolling_date_count: 90, no_earlier_than: nil, dependency_chart_block: nil

    project name: name do
      puts name
      self.anonymize if anonymize

      settings['blocked_link_text'] = ['is blocked by']
      self.settings.merge! settings

      status_category_mappings.each do |status, category|
        status_category_mapping status: status, category: category
      end

      file_prefix file_prefix
      download do
        self.rolling_date_count(rolling_date_count) if rolling_date_count
        self.no_earlier_than(no_earlier_than) if no_earlier_than
      end

      boards.each_key do |board_id|
        block = boards[board_id]
        if block == :default
          block = lambda do |_|
            start_at first_time_in_status_category('In Progress')
            stop_at still_in_status_category('Done')
          end
        end
        board id: board_id do
          cycletime(&block)
          expedited_priority_names 'Critical', 'Highest', 'Immediate Gating'
        end
      end

      file do
        file_suffix '.html'
        issues.reject! do |issue|
          %w[Sub-task Epic].include? issue.type
        end

        issues.reject! { |issue| ignore_issues.include? issue.key } if ignore_issues

        html_report do
          board_id default_board if default_board

          html "<H1>#{name}</H1>", type: :header
          boards.each_key do |id|
            board = find_board id
            html "<div><a href='#{board.url}'>#{id} #{board.name}</a></div>",
                 type: :header
          end

          discard_changes_before status_becomes: (starting_status || :backlog) # rubocop:disable Style/RedundantParentheses

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
          expedited_chart
          sprint_burndown
          estimate_accuracy_chart
          dependency_chart
        end
      end
    end
  end
end
