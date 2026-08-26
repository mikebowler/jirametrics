# frozen_string_literal: true

# Formats values for a Chart.js axis. Included by ChartBase and by the specs, which build the same
# strings to assert against.
module ChartFormat
  def chart_format object
    # MRI and JRuby once returned different strings from Time#to_s, which is why the format is
    # spelled out rather than left to to_s. They agree now (see jirametrics-uda), but the
    # assertions depend on this exact string and to_s promises nothing, so it stays.

    if object.is_a? Time
      object.strftime '%Y-%m-%dT%H:%M:%S%z' # => 2022-04-09T11:38:30-0700
    else
      object.to_s
    end
  end
end
