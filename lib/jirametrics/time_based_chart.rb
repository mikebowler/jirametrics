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

  # Converts the span between two Times into the selected cycletime unit.
  #
  # :days is deliberately different from the other units: it counts calendar days
  # inclusively in the configured timezone (opened and closed on the same day is
  # 1 day, crossing one midnight is 2), matching the working-days cycletime engine.
  # The elapsed units (:hours, :minutes) divide the wall-clock span and round up --
  # a partial unit still counts as one, so a 20-minute PR is 1 hour, never 0.
  def duration_in_unit from, to
    if @cycletime_unit == :days
      tz = timezone_offset || '+00:00'
      (to.getlocal(tz).to_date - from.getlocal(tz).to_date).to_i + 1
    else
      seconds_per_unit = { minutes: 60, hours: 3600 }[@cycletime_unit]
      ((to - from) / seconds_per_unit).ceil
    end
  end
end
