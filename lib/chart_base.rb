# frozen_string_literal: true

class ChartBase
  def render caller_binding, file
    basename = Pathname.new(File.realpath(file)).basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

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
