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
    caller_binding.eval "chart_id='chart#{next_id}'"

    erb = ERB.new File.read "html/#{$1}.erb"
    erb.result(caller_binding)
  end

  def next_id
    @@chart_counter += 1
  end

  def color_for type:
    @chart_colors[type] || 'black'
  end

  def label_days days
    "#{days} day#{'s' unless days == 1}"
  end

  def label_issues count
    "#{count} issue#{'s' unless count == 1}"
  end

  def daily_chart_dataset date_issues_list:, color:, label:, positive: true
    {
      type: 'bar',
      label: label,
      data: date_issues_list.collect do |date, issues|
        issues.sort! { |a, b| a.key_as_i <=> b.key_as_i }
        title = "#{label} (#{label_issues issues.size})"
        {
          x: date,
          y: positive ? issues.size : -issues.size,
          title: [title] + issues.collect { |i| "#{i.key} : #{i.summary.strip}#{" #{yield date, i}" if block_given?}" }
        }
      end,
      backgroundColor: color,
      borderRadius: positive ? 0 : 5
    }
  end

  def link_to_issue issue
    "<a href='#{issue.url}'>#{issue.key}</a>"
  end

  def collapsible_issues_panel issue_descriptions
    link_id = next_id
    issues_id = next_id

    result = String.new
    result << "[<a id=#{link_id.inspect} href='#'' onclick='expand_collapse(\"#{link_id}\", \"#{issues_id}\");"
    result << " return false;'>Show details</a>]"
    result << "<ul id=#{issues_id.inspect} style='display: none'>"
    issue_descriptions.sort { |a, b| a[0].key_as_i <=> b[0].key_as_i }.each do |issue, description|
      result << "<li><a href='#{issue.url}'>#{issue.key}</a> <i>#{issue.summary.inspect}</i> #{description}</li>"
    end
    result << '</ul>'
    result
  end

  def scan_data_quality issues
    checker = DataQualityChecker.new
    checker.issues = issues
    checker.cycletime = cycletime
    checker.board_metadata = board_metadata
    checker.possible_statuses = possible_statuses
    checker.run
    checker
  end
end
