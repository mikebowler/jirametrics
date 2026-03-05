# frozen_string_literal: true

require 'jirametrics/time_based_scatterplot'

class CycletimeScatterplot < TimeBasedScatterplot
  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text 'Cycletime Scatterplot'
    description_text <<-HTML
      <div class="p">
        This chart shows only completed work and indicates both what day it completed as well as
        how many days it took to get done. Hovering over a dot will show you the ID of the work item.
      </div>
      <div class="p">
        The #{color_block '--cycletime-scatterplot-overall-trendline-color'} line indicates the 85th
        percentile (<%= overall_percent_line %> days). 85% of all
        items on this chart fall on or below the line and the remaining 15% are above the line. 85%
        is a reasonable proxy for "most" so that we can say that based on this data set, we can
        predict that most work of this type will complete in <%= overall_percent_line %> days or
        less. The other lines reflect the 85% line for that respective type of work.
      </div>
      #{describe_non_working_days}
    HTML
    @x_axis_title = 'Date completed'
    @y_axis_title = 'Cycletime in days'

    init_configuration_block block do
      grouping_rules do |issue, rule|
        rule.label = issue.type
        rule.color = color_for type: issue.type
      end
    end
  end

  def all_items
    completed_issues_in_range include_unstarted: false
  end

  def x_value item
    item.board.cycletime.started_stopped_times(item).last
  end

  def y_value item
    item.board.cycletime.cycletime(item)
  end

  def title_value item
    hint = @issue_hints&.fetch(item, nil)
    "#{item.key} : #{item.summary} (#{label_days(y_value(item))})#{" #{hint}" if hint}"
  end

  # Kept for backwards compatibility with existing callers and specs
  alias data_for_issue data_for_item
end
