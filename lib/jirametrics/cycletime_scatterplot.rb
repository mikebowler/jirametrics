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
      <%= percentile_description %>
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

  # Days-only until the working-days cycletime engine grows sub-day resolution. Inherited from
  # TimeBasedChart so the option exists, but the unbuilt path fails loudly rather than mislabelling
  # the axis while the value stays in days. See jirametrics-en5.
  def cycletime_unit unit
    raise NotImplementedError, "#{self.class} only supports :days for now (see jirametrics-en5)" unless unit == :days
  end

  def minimum_y_value
    1 # Values under 1 day are data quality problems; they're flagged in the quality report instead
  end

  def all_items
    completed_issues_in_range include_unstarted: false
  end

  def x_value item
    item.started_stopped_times.last
  end

  def y_value item
    item.board.cycletime.cycletime(item)
  end

  def title_value item, rules: nil
    hint = @issue_hints&.fetch(item, nil)
    "#{item.key} : #{item.summary} (#{label_days(y_value(item))})#{" #{hint}" if hint}"
  end

  # Kept for backwards compatibility with existing callers and specs
  alias data_for_issue data_for_item

  # The prose follows the configuration. With one percentile we keep the original "proxy for
  # most" framing; with several that framing makes no sense, and with none there is nothing to
  # describe. Values come from percentage_lines because run has already computed them, and
  # because this string is not run through ERB a second time.
  def percentile_description
    overall_lines = percentage_lines.select { |line| line[:group_label].nil? }
    return '' if overall_lines.empty?

    if overall_lines.size == 1
      single_percentile_description(overall_lines.first)
    else
      multi_percentile_description(overall_lines)
    end
  end

  def single_percentile_description line
    percentile = line[:percentile]
    days = line[:value]
    <<-HTML
      <div class="p">
        The #{color_block '--cycletime-scatterplot-overall-trendline-color'} line indicates the
        #{percentile}th percentile (#{days} days). #{percentile}% of all
        items on this chart fall on or below the line and the remaining #{100 - percentile}% are
        above the line. #{percentile}% is a reasonable proxy for "most" so that we can say that
        based on this data set, we can predict that most work of this type will complete in
        #{days} days or less. The other lines reflect the #{percentile}% line for that
        respective type of work.
      </div>
    HTML
  end

  def multi_percentile_description lines
    described = lines.collect { |line| "#{line[:percentile]}th at #{label_days line[:value]}" }
    <<-HTML
      <div class="p">
        The #{color_block '--cycletime-scatterplot-overall-trendline-color'} lines indicate the
        #{described.join ', '} percentiles across all items on this chart. If a line sits at N
        days then that percentage of items completed in N days or less. The same percentiles are
        drawn for each type of work in that type's own colour. Hover any line to see its value.
      </div>
    HTML
  end
end
