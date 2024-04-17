# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
#
# See https://github.com/mikebowler/jirametrics/wiki/Examples-folder for more
class Exporter
  def standard_project name:, file_prefix:, ignore_issues: nil, starting_status: nil, boards: {},
      default_board: nil, anonymize: false

    project name: name do
      puts name
      self.anonymize if anonymize

      settings['blocked_link_text'] = ['is blocked by']
      file_prefix file_prefix
      download do
        rolling_date_count 90
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

          discard_changes_before status_becomes: (starting_status || :backlog)

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
          daily_wip_chart do
            header_text 'Daily WIP by Parent'
            description_text <<-TEXT
              How much work is in progress, grouped by the parent of the issue. This will give us an
              indication of how focused we are on higher level objectives. If there are many parent
              tickets in progress at the same time, either this team has their focus scattered or we
              aren't doing a good job of
              <a href="https://improvingflow.com/2024/02/21/slicing-epics.html">splitting those parent
              tickets</a>. Neither of those is desirable.
            TEXT
            grouping_rules do |issue, rules|
              rules.label = issue.parent&.key || 'No parent'
              rules.color = 'white' if rules.label == 'No parent'
            end
          end
          expedited_chart
          sprint_burndown
          story_point_accuracy_chart

          dependency_chart do
            link_rules do |link, rules|
              case link.name
              when 'Cloners'
                rules.ignore
              when 'Dependency', 'Blocks', 'Parent/Child', 'Cause', 'Satisfy Requirement', 'Relates'
                rules.merge_bidirectional keep: 'outward'
                rules.merge_bidirectional keep: 'outward'
              when 'Sync'
                rules.use_bidirectional_arrows
              else
                # This is a link type that we don't recognized. Dump it to standard out to draw attention
                # to it.
                puts "name=#{link.name}, label=#{link.label}"
              end
            end
          end
        end
      end
    end
  end
end
