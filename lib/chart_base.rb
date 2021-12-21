# frozen_string_literal: true

class ChartBase
  @@chart_counter = 0

  def render caller_binding, file
    basename = Pathname.new(File.realpath(file)).basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

    # Insert a 'random' chart_id so that all the chart names on the page are unique
    caller_binding.eval "chart_id='chart#{@@chart_counter += 1}'"

    erb = ERB.new File.read "html/#{$1}.erb"
    erb.result(caller_binding)
  end

  def color_for type:
    case type.downcase
    when 'story' then 'green'
    when 'task' then 'blue'
    when 'bug', 'defect' then 'orange'
    when 'spike' then 'gray'
    else 'black'
    end
  end

  def label_days days
    "#{days} day#{'s' unless days == 1}"
  end
end
