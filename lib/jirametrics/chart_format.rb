# frozen_string_literal: true

# Formats values for a Chart.js axis. Included by ChartBase and by the specs, which build the same
# strings to assert against.
module ChartFormat
  def chart_format object
    # Not all ruby versions return the same string for to_s so we force to a known format.

    if object.is_a? Time
      object.strftime '%Y-%m-%dT%H:%M:%S%z' # => 2022-04-09T11:38:30-0700
    else
      object.to_s
    end
  end
end
