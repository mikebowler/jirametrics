# frozen_string_literal: true

require 'jirametrics/groupable_issue_chart'

class FlowEfficiencyScatterplot < ChartBase
  include GroupableIssueChart

  attr_accessor :possible_statuses

  def initialize block
    super()

    header_text 'Flow Efficiency'
    description_text <<-HTML
      <div class="p">
        This chart shows the active time against the the total time spent on a ticket.
        <a href="https://improvingflow.com/2024/07/06/flow-efficiency.html">Flow  efficiency</a> is the ratio
        between these two numbers.
      </div>
      <div class="p">
        <math>
          <mn>Flow efficiency (%)</mn>
          <mo>=</mo>
          <mfrac>
            <mrow><mn>Time adding value</mn></mrow>
            <mrow><mn>Total time</mn></mrow>
          </mfrac>
        </math>
      </div>
      <div style="background: yellow">Note that for this calculation to be accurate, we must be moving items into a
        blocked or stalled state the moment we stop working on it, and most teams don't do that.
        So be aware that your team may have to change their behaviours if you want this chart to be useful.
      </div>
    HTML

    init_configuration_block block do
      grouping_rules do |issue, rule|
        active_time, total_time = issue.flow_efficiency_numbers end_time: time_range.end
        flow_efficiency = active_time * 100.0 / total_time

        if flow_efficiency > 99.0
          rule.label = '~100%'
          rule.color = 'green'
        elsif flow_efficiency < 30.0
          rule.label = '< 30%'
          rule.color = 'orange'
        else
          rule.label = 'The rest'
          rule.color = 'black'
        end
      end
    end

    @percentage_lines = []
    @highest_cycletime = 0
  end

  def run
    data_sets = group_issues(completed_issues_in_range include_unstarted: false).filter_map do |rules, issues|
      create_dataset(issues: issues, label: rules.label, color: rules.color)
    end

    return "<h1>#{@header_text}</h1>No data matched the selected criteria. Nothing to show." if data_sets.empty?

    wrap_and_render(binding, __FILE__)
  end

  def to_days seconds
    seconds / 60 / 60 / 24
  end

  def create_dataset issues:, label:, color:
    return nil if issues.empty?

    data = issues.filter_map do |issue|
      active_time, total_time = issue.flow_efficiency_numbers(
        end_time: time_range.end, settings: settings
      )

      active_days = to_days(active_time)
      total_days = to_days(total_time)
      flow_efficiency = active_time * 100.0 / total_time

      if flow_efficiency.nan?
        # If this happens then something is probably misconfigured. We've seen it in production though
        # so we have to handle it.
        file_system.log(
          "Issue(#{issue.key}) flow_efficiency: NaN, active_time: #{active_time}, total_time: #{total_time}"
        )
        flow_efficiency = 0.0
      end

      {
        y: active_days,
        x: total_days,
        title: [
          "#{issue.key} : #{issue.summary}, flow efficiency: #{flow_efficiency.to_i}%," \
          " total: #{total_days.round(1)} days," \
          " active: #{active_days.round(1)} days"
        ]
      }
    end
    {
      label: label,
      data: data,
      fill: false,
      showLine: false,
      backgroundColor: color
    }
  end
end
