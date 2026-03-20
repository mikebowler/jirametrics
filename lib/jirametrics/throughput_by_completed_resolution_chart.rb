# frozen_string_literal: true

require 'jirametrics/throughput_chart'

class ThroughputByCompletedResolutionChart < ThroughputChart
  def initialize block
    super
    header_text 'Throughput, grouped by completion status and resolution'
    description_text '<h2>Number of items completed, grouped by completion status and resolution</h2>'
  end

  def default_grouping_rules issue, rules
    status, resolution = issue.status_resolution_at_done
    if resolution
      rules.label = "#{status.name}:#{resolution}"
      rules.label_hint = "Status: #{status.name.inspect}:#{status.id}, resolution: #{resolution.inspect}"
    else
      rules.label = status.name
      rules.label_hint = "Status: #{status.name.inspect}:#{status.id}"
    end
  end
end
