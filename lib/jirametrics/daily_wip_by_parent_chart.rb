# frozen_string_literal: true

require 'jirametrics/daily_wip_chart'

class DailyWipByParentChart < DailyWipChart
  def default_header_text
    'Daily WIP, grouped by the parent ticket (Epic, Feature, etc)'
  end

  def default_description_text
    <<-HTML
      <div class="p">
        How much work is in progress, grouped by the parent of the issue. This will give us an
        indication of how focused we are on higher level objectives. If there are many parent
        tickets in progress at the same time, either this team has their focus scattered or we
        aren't doing a good job of
        <a href="https://improvingflow.com/2024/02/21/slicing-epics.html">splitting those parent
        tickets</a>. Neither of those is desirable.
      </div>
      <div class="p">
        The #{color_block '--body-background'} shading at the top shows items that don't have a parent
        at all.
      </div>
      #{describe_non_working_days}
    HTML
  end

  def default_grouping_rules issue:, rules:
    parent = issue.parent&.key
    if parent
      rules.label = parent
    else
      rules.label = 'No parent'
      rules.group_priority = 1000
      rules.color = '--body-background'
    end
  end
end
