# frozen_string_literal: true

# This file is really intended to give you ideas about how you might configure your own reports, not
# as a complete setup that will work in every case.
#
# See https://github.com/mikebowler/jirametrics/wiki/Examples-folder for more details
#
# The point of an AGGREGATED report is that we're now looking at a higher level. We might use this in a
# S2 meeting (Scrum of Scrums) to talk about the things that are happening across teams, not within a
# single team. For that reason, we look at slightly different things that we would on a single team board.

class Exporter
  def aggregated_project name:, project_names:, settings: {}
    project name: name do
      puts name
      self.settings.merge! settings

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
            # In an aggregated report, we likely only care about items that are old so exclude anything
            # under 21 days.
            age_cutoff 21
          end

          dependency_chart do
            header_text 'Dependencies across boards'
            description_text 'We are only showing dependencies across boards.'

            # By default, the issue doesn't show what board it's on and this is important for an
            # aggregated view
            issue_rules do |issue, rules|
              key = issue.key
              key = "<S>#{key} </S> " if issue.status.category_name == 'Done'
              rules.label = "<#{key} [#{issue.type}]<BR/>#{issue.board.name}<BR/>#{word_wrap issue.summary}>"
            end

            link_rules do |link, rules|
              # By default, the dependency chart shows everything. Clean it up a bit.
              case link.name
              when 'Cloners'
                # We don't want to see any clone links at all.
                rules.ignore
              when 'Blocks'
                # For blocks, by default Jira will have links going both
                # ways and we want them only going one way. Also make the
                # link red.
                rules.merge_bidirectional keep: 'outward'
                rules.line_color = 'red'
              end

              # Because this is the aggregated view, let's hide any link that doesn't cross boards.
              rules.ignore if link.origin.board == link.other_issue.board
            end
          end
        end
      end
    end
  end
end
