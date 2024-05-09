# frozen_string_literal: true

class ChartBase
  attr_accessor :timezone_offset, :board_id, :all_boards, :date_range,
    :time_range, :data_quality, :holiday_dates, :settings
  attr_writer :aggregated_project
  attr_reader :issues, :canvas_width, :canvas_height

  @@chart_counter = 0

  def initialize
    @chart_colors = {
      'Story'  => CssVariable['--type-story-color'],
      'Task'   => CssVariable['--type-task-color'],
      'Bug'    => CssVariable['--type-bug-color'],
      'Defect' => CssVariable['--type-bug-color'],
      'Spike'  => CssVariable['--type-spike-color']
    }
    @canvas_width = 800
    @canvas_height = 200
    @canvas_responsive = true
  end

  def aggregated_project?
    @aggregated_project
  end

  def render caller_binding, file
    pathname = Pathname.new(File.realpath(file))
    basename = pathname.basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

    # Insert a incrementing chart_id so that all the chart names on the page are unique
    caller_binding.eval "chart_id='chart#{next_id}'" # chart_id=chart3

    @html_directory = "#{pathname.dirname}/html"
    erb = ERB.new File.read "#{@html_directory}/#{$1}.erb"
    erb.result(caller_binding)
  end

  # Render the file and then wrap it with standard headers and quality checks.
  def wrap_and_render caller_binding, file
    result = +''
    result << "<h1>#{@header_text}</h1>" if @header_text
    result << ERB.new(@description_text).result(caller_binding) if @description_text
    result << render(caller_binding, file)
    result
  end

  def next_id
    @@chart_counter += 1
  end

  def color_for type:
    @chart_colors[type] ||= random_color
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
        issues.sort_by!(&:key_as_i)
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

  def link_to_issue issue, args = {}
    attributes = { class: 'issue_key' }
      .merge(args)
      .collect { |key, value| "#{key}='#{value}'" }
      .join(' ')
    "<a href='#{issue.url}' #{attributes}>#{issue.key}</a>"
  end

  def collapsible_issues_panel issue_descriptions, *args
    link_id = next_id
    issues_id = next_id

    issue_descriptions.sort! { |a, b| a[0].key_as_i <=> b[0].key_as_i }
    erb = ERB.new File.read "#{@html_directory}/collapsible_issues_panel.erb"
    erb.result(binding)
  end

  def holidays date_range: @date_range
    result = []
    start_date = nil
    end_date = nil

    date_range.each do |date|
      if date.saturday? || date.sunday? || holiday_dates.include?(date)
        if start_date.nil?
          start_date = date
        else
          end_date = date
        end
      elsif start_date
        result << (start_date..(end_date || start_date))
        start_date = nil
        end_date = nil
      end
    end
    result
  end

  # Return only the board columns for the current board.
  def current_board
    if @board_id.nil?
      case @all_boards.size
      when 0
        raise 'Couldn\'t find any board configurations. Ensure one is set'
      when 1
        return @all_boards.values[0]
      else
        raise "Must set board_id so we know which to use. Multiple boards found: #{@all_boards.keys.inspect}"
      end
    end

    @all_boards[@board_id]
  end

  def completed_issues_in_range include_unstarted: false
    issues.select do |issue|
      cycletime = issue.board.cycletime
      stopped_time = cycletime.stopped_time(issue)
      started_time = cycletime.started_time(issue)

      stopped_time &&
        date_range.include?(stopped_time.to_date) && # Remove outside range
        (include_unstarted || (started_time && (stopped_time >= started_time)))
    end
  end

  def sprints_in_time_range board
    board.sprints.select do |sprint|
      sprint_end_time = sprint.completed_time || sprint.end_time
      sprint_start_time = sprint.start_time
      next false if sprint_start_time.nil?

      time_range.include?(sprint_start_time) || time_range.include?(sprint_end_time) ||
        (sprint_start_time < time_range.begin && sprint_end_time > time_range.end)
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

  def format_integer number
    number.to_s.reverse.scan(/.{1,3}/).join(',').reverse
  end

  def format_status name_or_id, board:, is_category: false
    begin
      statuses = board.possible_statuses.expand_statuses([name_or_id])
    rescue RuntimeError => e
      return "<span style='color: red'>#{name_or_id}</span>" if e.message.match?(/^Status not found:/)

      throw e
    end
    raise "Expected exactly one match and got #{statuses.inspect} for #{name_or_id.inspect}" if statuses.size > 1

    status = statuses.first
    color = status_category_color status

    text = is_category ? status.category_name : status.name
    "<span title='Category: #{status.category_name}'>#{color_block color.name} #{text}</span>"
  end

  def status_category_color status
    case status.category_name
    when nil then 'black'
    when 'To Do' then CssVariable['--status-category-todo-color']
    when 'In Progress' then CssVariable['--status-category-inprogress-color']
    when 'Done' then CssVariable['--status-category-done-color']
    end
  end

  def random_color
    "##{Random.bytes(3).unpack1('H*')}"
  end

  def canvas width:, height:, responsive: true
    @canvas_width = width
    @canvas_height = height
    @canvas_responsive = responsive
  end

  def canvas_responsive?
    @canvas_responsive
  end

  def filter_issues &block
    @filter_issues_block = block
  end

  def issues= issues
    @issues = issues
    return unless @filter_issues_block

    @issues = issues.filter_map { |i| @filter_issues_block.call(i) }.uniq
    puts @issues.collect(&:key).join(', ')
  end

  def color_block color, title: nil
    result = +''
    result << "<div class='color_block' style='background: var(#{color});'"
    result << " title=#{title.inspect}" if title
    result << '></div>'
    result
  end

  def describe_non_working_days
    <<-TEXT
      <div class='p'>
        The #{color_block '--non-working-days-color'} vertical bars indicate non-working days; weekends
        and any other holidays mentioned in the configuration.
      </div>
    TEXT
  end  
end
