# frozen_string_literal: true

class CycletimeHistogram < ChartBase
  attr_accessor :issues, :cycletime, :possible_statuses, :date_range

  def initialize block = nil
    super()
    @group_by_block = block || ->(issue) { [issue.type, color_for(type: issue.type)] }
  end

  def run
    stopped_issues = completed_issues_in_range include_unstarted: true

    data_quality = scan_data_quality(stopped_issues)

    # For the histogram, we only want to consider items that have both a start and a stop time.
    histogram_issues = stopped_issues.select { |issue| @cycletime.started_time(issue) }

    type_color_groupings = histogram_issues.collect { |issue| @group_by_block.call(issue) }.uniq
    data_sets = type_color_groupings.collect do |type, color|
      data_set_for(
        histogram_data: histogram_data_for(
          issues: histogram_issues.select { |issue| @group_by_block.call(issue) == [type, color] }
        ),
        label: type,
        color: color
      )
    end

    render(binding, __FILE__)
  end

  def histogram_data_for issues:
    count_hash = {}
    issues.each do |issue|
      days = @cycletime.cycletime(issue)
      count_hash[days] = (count_hash[days] || 0) + 1
    end
    count_hash
  end

  def data_set_for histogram_data:, label:, color:
    keys = histogram_data.keys.sort
    {
      type: 'bar',
      label: label,
      data: keys.sort.collect do |key|
        next if histogram_data[key].zero?

        {
          x: key,
          y: histogram_data[key],
          title: "#{histogram_data[key]} items completed in #{label_days key}"
        }
      end.compact,
      backgroundColor: color,
      borderRadius: 0
    }
  end
end
