# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
#
# See https://github.com/mikebowler/jirametrics/wiki/Examples-folder for moreclass Exporter
class Exporter
  def aggregated_project name:, project_names:
    project name: name do
      puts name
      aggregate do
        project_names.each do |project_name|
          include_issues_from project_name
        end
      end

      file_prefix name

      file do
        file_suffix '.html'
        issues.reject! do |issue|
          %w[Sub-task Epic].include? issue.type
        end

        html_report do
          cycletime_scatterplot do
            show_trend_lines
            grouping_rules do |issue, rules|
              rules.label = issue.board.name
            end
          end
          # aging_work_in_progress_chart
          daily_wip_chart do
            header_text 'Daily WIP by Parent'
            description_text <<-TEXT
              <p>How much work is in progress, grouped by the parent of the issue. This will give us an
              indication of how focused we are on higher level objectives. If there are many parent
              tickets in progress at the same time, either this team has their focus scattered or we
              aren't doing a good job of
              <a href="https://improvingflow.com/2024/02/21/slicing-epics.html">splitting those parent
              tickets</a>. Neither of those is desirable.</p>
              <p>If you're expecting all work items to have parents and there are a lot that don't,
              that's also something to look at. Consider whether there is even value in aggregating
              these projects if they don't share parent dependencies. Aggregation helps us when we're
              looking at related work and if there aren't parent dependencies then the work may not
              be related.</p>
            TEXT
            grouping_rules do |issue, rules|
              rules.label = issue.parent&.key || 'No parent'
              rules.color = 'white' if rules.label == 'No parent'
            end
          end
          aging_work_table do
            age_cutoff 21
          end
        end
      end
    end
  end
end
