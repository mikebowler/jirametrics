# frozen_string_literal: true

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
          aging_work_in_progress_chart
          aging_work_table do
            age_cutoff 21
          end
        end
      end
    end
  end
end