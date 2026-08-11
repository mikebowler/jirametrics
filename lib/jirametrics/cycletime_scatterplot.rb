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

  # The number that the "reasonable proxy for most" claim is actually about. That claim is only
  # defensible near this value: at the median half the work runs longer, and at the 98th you are
  # describing the worst case, not the typical one. So the sentence appears when this percentile
  # is on the chart and is silently dropped when it is not, rather than being reworded into
  # something that sounds authoritative and is wrong.
  PROXY_FOR_MOST_PERCENTILE = 85

  # The prose follows the configuration, so it has to read well for one percentile or several,
  # and say nothing at all for none. Values come from percentage_lines because run has already
  # computed them, and because this string is not run through ERB a second time.
  def percentile_description
    overall_lines = percentage_lines.select { |line| line[:dataset_index].nil? }
    return '' if overall_lines.empty?

    sentences = [
      percentile_summary_sentence(overall_lines),
      proxy_for_most_sentence(overall_lines),
      per_type_sentence(overall_lines)
    ].compact
    <<-HTML
      <div class="p">
        #{sentences.join ' '}
      </div>
    HTML
  end

  # Mechanical and true whatever the configured percentiles are. Singular phrasing is preserved
  # word for word from the original so the default chart reads exactly as it always has.
  def percentile_summary_sentence lines
    swatch = color_block '--cycletime-scatterplot-overall-trendline-color'
    if lines.size == 1
      percentile = lines.first[:percentile]
      "The #{swatch} line indicates the #{ordinal percentile} percentile " \
        "(#{lines.first[:value]} days). #{percentile}% of all items on this chart fall on or " \
        "below the line and the remaining #{100 - percentile}% are above the line."
    else
      # No values inline here. With several lines the sentence turns into a wall of parentheses,
      # and each value is already on the line's hover label and in that group's legend entry.
      described = lines.collect { |line| ordinal line[:percentile] }
      "The #{swatch} lines indicate the #{comma_and described} percentiles of all items on " \
        'this chart. For each line, that percentage of items fall on or below it and the rest ' \
        'are above.'
    end
  end

  # Only emitted when 85 is actually among the configured percentiles. See PROXY_FOR_MOST_PERCENTILE.
  def proxy_for_most_sentence lines
    line = lines.find { |candidate| candidate[:percentile] == PROXY_FOR_MOST_PERCENTILE }
    return nil unless line

    "#{PROXY_FOR_MOST_PERCENTILE}% is a " \
      '<a href="https://jirametrics.org/faq/#why-85">reasonable proxy</a> for "most" so that we ' \
      'can say that based on this data set, we can predict that most work of this type will ' \
      "complete in #{line[:value]} days or less."
  end

  def per_type_sentence lines
    if lines.size == 1
      "The other lines reflect the #{lines.first[:percentile]}% line for that respective type of work."
    else
      'Each type of work also gets its own lines in its own colour, at whichever percentiles ' \
        'were configured for that type. Hover any line to see which one it is and its value.'
    end
  end

  # 1st, 2nd, 3rd, 4th ... 11th, 12th, 13th ... 21st. Percentiles are validated to 0..100, and
  # blindly appending "th" would render "1th" and "22th".
  def ordinal number
    suffix =
      if [11, 12, 13].include?(number % 100)
        'th'
      else
        { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(number % 10, 'th')
      end
    "#{number}#{suffix}"
  end

  def comma_and phrases
    return phrases.join ' and ' if phrases.size <= 2

    "#{phrases[0..-2].join ', '} and #{phrases.last}"
  end
end
