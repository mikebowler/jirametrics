# frozen_string_literal: true

class ChartBase
  @@chart_counter = 0

  def initialize
    @chart_colors = {
      'Story' => 'green',
      'Task' => 'blue',
      'Bug' => 'orange',
      'Defect' => 'orange',
      'Spike' => 'gray'
    }
  end

  def render caller_binding, file
    basename = Pathname.new(File.realpath(file)).basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

    # Insert a 'random' chart_id so that all the chart names on the page are unique
    caller_binding.eval "chart_id='chart#{@@chart_counter += 1}'"

    erb = ERB.new File.read "html/#{$1}.erb"
    erb.result(caller_binding)
  end

  def color_for type:
    @chart_colors[type] || 'black'
  end

  def label_days days
    "#{days} day#{'s' unless days == 1}"
  end

  def daily_chart_dataset date_issues_list:, color:, label:, positive: true
    {
      type: 'bar',
      label: label,
      data: date_issues_list.collect do |date, issues|
        {
          x: date,
          y: positive ? issues.size : -issues.size,
          title: [label] + issues.collect { |i| "#{i.key} : #{i.summary}#{yield date, i if block_given?}" }.sort
        }
      end,
      backgroundColor: color,
      borderRadius: positive ? 0 : 5
    }
  end
end
