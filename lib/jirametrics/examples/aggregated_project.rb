# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
#
# The point of an AGGREGATED report is that we're now looking at a higher level. We might use this in a
# S2 meeting (Scrum of Scrums) to talk about the things that are happening across teams, not within a
# single team. For that reason, we look at slightly different things that we would on a single team board.

class Exporter
  def aggregated_project name:, project_names:, settings: {}
    project name: name do
      puts name
      file_prefix name
      self.settings.merge! settings

      aggregate do
        project_names.each do |project_name|
          include_issues_from project_name
        end
      end

      file do
        file_suffix '.html'
        issues.reject! do |issue|
          %w[Sub-task Epic].include? issue.type
        end

        html_report do
          html '<h1>Boards included in this report</h1><ul>', type: :header
          board_lines = []
          included_projects.each do |project|
            project.all_boards.each_value do |board|
              board_lines << "<a href='#{project.get_file_prefix}.html'>#{board.name}</a> from project #{project.name}"
            end
          end
          board_lines.sort.each { |line| html "<li>#{line}</li>", type: :header }
          html '</ul>', type: :header

          cycletime_scatterplot do
            show_trend_lines
            # For an aggregated report we group by board rather than by type
            grouping_rules do |issue, rules|
              rules.label = issue.board.name
            end
          end
          # aging_work_in_progress_chart
          daily_wip_by_parent_chart do
            # When aggregating, the chart tends to need more vertical space
            canvas height: 400, width: 800
          end
          aging_work_table do
            # In an aggregated report, we likely only care about items that are old so exclude anything
            # under 21 days.
            age_cutoff 21
          end

          dependency_chart do
            header_text 'Dependencies across boards'
            description_text 'We are only showing dependencies across boards.'

            # By default, the issue doesn't show what board it's on and this is important for an
            # aggregated view
            chart = self
            issue_rules do |issue, rules|
              chart.default_issue_rules.call(issue, rules)
              rules.label = rules.label.split('<BR/>').insert(1, "Board: #{issue.board.name}").join('<BR/>')
            end

            link_rules do |link, rules|
              chart.default_link_rules.call(link, rules)

              # Because this is the aggregated view, let's hide any link that doesn't cross boards.
              rules.ignore if link.origin.board == link.other_issue.board
            end
          end
        end
      end
    end
  end
end
