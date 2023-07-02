# frozen_string_literal: true

class Exporter
  def standard_project name:, file_prefix:, ignore_issues: nil, starting_status: nil, boards: {}, default_board: nil
    project name: name do
      puts name

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

          html "<H1>#{file_prefix}</H1>", type: :header
          boards.each_key do |id|
            board = find_board id
            html "<div><a href='#{board.url}'>#{id} #{board.name}</a></div>",
                 type: :header
          end

          discard_changes_before status_becomes: (starting_status || :backlog)

          hierarchy_table
          cycletime_scatterplot do
            show_trend_lines
          end
          cycletime_scatterplot do # Epics
            header_text 'Parents only'
            filter_issues { |i| i.parent }
          end
          cycletime_histogram
          cycletime_histogram do
            grouping_rules do |issue, rules|
              rules.label = issue.board.cycletime.stopped_time(issue).to_date.strftime('%b %Y')
            end
          end

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
          expedited_chart
          sprint_burndown
          story_point_accuracy_chart
          story_point_accuracy_chart do
            header_text nil
            description_text nil
            y_axis(sort_order: %w[Story Task Defect], label: 'TShirt Sizes') { |issue, _started_time| issue.type }
          end

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
                #   rules.line_color = 'red'
              else
                puts "name=#{link.name}, label=#{link.label}"
              end
            end
          end
        end
      end
    end
  end
end
