# frozen_string_literal: true

require 'jirametrics/chart_base'

# Common base for every cycle-time chart. It owns the cycletime *unit system* --
# which unit the value axis is expressed in and how a raw value is labelled --
# because that concern is core to any chart that plots a cycle time, not a
# cross-cutting add-on. The scatter/histo split lives one level down (in
# TimeBasedScatterplot / TimeBasedHistogram, which supply the value_axis_title=
# hook so this class doesn't need to know which axis carries the value); the
# PR-vs-issue split lives one level below that.
class TimeBasedChart < ChartBase
  def initialize
    super

    @cycletime_unit = :days
  end

  def cycletime_unit unit
    unless %i[minutes hours days].include?(unit)
      raise ArgumentError, "cycletime_unit must be :minutes, :hours, or :days, got #{unit.inspect}"
    end

    @cycletime_unit = unit
    self.value_axis_title = "Cycle time in #{unit}"
  end

  def label_cycletime value
    case @cycletime_unit
    when :minutes then label_minutes(value)
    when :hours then label_hours(value)
    when :days then label_days(value)
    end
  end
end
