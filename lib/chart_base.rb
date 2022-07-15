# frozen_string_literal: true

class ChartBase
  attr_accessor :timezone_offset, :board_id, :all_board_columns, :cycletime, :issues, :date_range, 
    :time_range, :sprints_by_board

  @@chart_counter = 0

  def initialize
    @chart_colors = {
      'dark:Story' => 'green',
      'dark:Task' => 'blue',
      'dark:Bug' => 'orange',
      'dark:Defect' => 'orange',
      'dark:Spike' => 'gray',
      'light:Story' => '#90EE90',
      'light:Task' => '#87CEFA',
      'light:Bug' => '#ffdab9',
      'light:Defect' => 'orange',
      'light:Epic' => '#fafad2',
      'light:Spike' => 'lightgray'
    }
  end

  def render caller_binding, file
    basename = Pathname.new(File.realpath(file)).basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

    # Insert a incrementing chart_id so that all the chart names on the page are unique
    caller_binding.eval "chart_id='chart#{next_id}'"

    erb = ERB.new File.read "html/#{$1}.erb"
    erb.result(caller_binding)
  end

  # Render the file and then wrap it with standard headers and quality checks.
  def wrap_and_render caller_binding, file
    result = String.new
    result << "<h1>#{@header_text}</h1>" if @header_text
    result << "<div>#{@description_text}</div>" if @description_text
    result << render(caller_binding, file)
    result
  end

  def next_id
    @@chart_counter += 1
  end

  def color_for type:, shade: :dark
    @chart_colors["#{shade}:#{type}"] || 'red'
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
    if issue.url
      "<a href='#{issue.url}' class='issue_key'>#{issue.key}</a>"
    else
      issue.key
    end
  end

  def collapsible_issues_panel issue_descriptions
    link_id = next_id
    issues_id = next_id

    issue_descriptions.sort! { |a, b| a[0].key_as_i <=> b[0].key_as_i }
    erb = ERB.new File.read 'html/collapsible_issues_panel.erb'
    erb.result(binding)
  end

  def scan_data_quality issues
    checker = DataQualityChecker.new
    checker.issues = issues
    checker.cycletime = cycletime
    checker.board_columns = board_columns
    checker.possible_statuses = possible_statuses
    checker.run
    checker
  end

  def holidays date_range=@date_range
    result = []
    date_range.each do |date|
      result << (date..date + 1) if date.wday == 6
    end
    result
  end

  # Return only the board columns for the current board.
  def board_columns
    if @board_id.nil?
      case @all_board_columns.size
      when 0
        raise 'Couldn\'t find any board configurations. Ensure one is set'
      when 1
        return @all_board_columns.values[0]
      else
        raise "Must set board_id so we know which to use. Multiple boards found: #{@all_board_columns.keys.inspect}"
      end
    end

    @all_board_columns[@board_id]
  end

  def completed_issues_in_range include_unstarted:
    issues.select do |issue|
      stopped_time = cycletime.stopped_time(issue)
      stopped_time && date_range.include?(stopped_time.to_date) && (include_unstarted || cycletime.started_time(issue))
    end
  end

  def sprints_in_time_range
    sprints_by_board[board_id]&.select do |sprint|
      time_range.include?(sprint.start_time) # && time_range.include?(sprint.end_time)
    end || []
  end

  def chart_format object
    if object.is_a? Time
      # "2022-04-09T11:38:30-07:00"
      object.strftime '%Y-%m-%dT%H:%M:%S%z'
    else
      object.to_s
    end
  end

  def header_text text
    @header_text = text
  end

  def description_text text
    @description_text = text
  end
end
