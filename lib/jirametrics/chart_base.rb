# frozen_string_literal: true

class ChartBase
  attr_accessor :timezone_offset, :board_id, :all_boards, :date_range,
    :time_range, :data_quality, :holiday_dates, :settings, :issues, :file_system,
    :atlassian_document_format
  attr_writer :aggregated_project
  attr_reader :canvas_width, :canvas_height

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

  def html_directory
    pathname = Pathname.new(File.realpath(__FILE__))
    "#{pathname.dirname}/html"
  end

  def render caller_binding, file
    pathname = Pathname.new(File.realpath(file))
    basename = pathname.basename.to_s
    raise "Unexpected filename #{basename.inspect}" unless basename =~ /^(.+)\.rb$/

    # Insert a incrementing chart_id so that all the chart names on the page are unique
    caller_binding.eval "chart_id='chart#{next_id}'" # chart_id=chart3

    erb = ERB.new file_system.load "#{html_directory}/#{$1}.erb"
    erb.result(caller_binding)
  end

  def render_top_text caller_binding
    result = +''
    result << "<h1 class='foldable'>#{@header_text}</h1>" if @header_text
    result << ERB.new(@description_text).result(caller_binding) if @description_text
    result
  end

  # Render the file and then wrap it with standard headers and quality checks.
  def wrap_and_render caller_binding, file
    result = +''
    result << render_top_text(caller_binding)
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
    return 'unknown' if days.nil?

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
    erb = ERB.new file_system.load File.join(html_directory, 'collapsible_issues_panel.erb')
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

  def working_days_annotation
    holidays.each_with_index.collect do |range, index|
      <<~TEXT
        holiday#{index}: {
          drawTime: 'beforeDraw',
          type: 'box',
          xMin: '#{range.begin}T00:00:00',
          xMax: '#{range.end}T23:59:59',
          backgroundColor: #{CssVariable.new('--non-working-days-color').to_json},
          borderColor: #{CssVariable.new('--non-working-days-color').to_json}
        },
      TEXT
    end.join
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
      started_time, stopped_time = cycletime.started_stopped_times(issue)

      stopped_time &&
        date_range.include?(stopped_time.to_date) && # Remove outside range
        (include_unstarted || (started_time && (stopped_time >= started_time)))
    end
  end

  def chart_format object
    if object.is_a? Time
      # "2022-04-09T11:38:30-07:00"
      object.strftime '%Y-%m-%dT%H:%M:%S%z'
    else
      object.to_s
    end
  end

  def header_text text = :none
    @header_text = text unless text == :none
    @header_text
  end

  def description_text text = :none
    @description_text = text unless text == :none
    @description_text
  end

  # Convert a number like 1234567 into the string "1,234,567"
  def format_integer number
    number.to_s.reverse.scan(/.{1,3}/).join(',').reverse
  end

  # object will be either a Status or a ChangeItem
  # if it's a ChangeItem then use_old_status will specify whether we're using the new or old
  # Either way, is_category will format the category rather than the status
  def format_status object, board:, is_category: false, use_old_status: false
    status = nil
    error_message = nil

    case object
    when ChangeItem
      id = use_old_status ? object.old_value_id : object.value_id
      status = board.possible_statuses.find_by_id(id)
      if status.nil?
        error_message = use_old_status ? object.old_value : object.value
      end
    when Status
      status = object
    else
      raise "Unexpected type: #{object.class}"
    end

    return "<span style='color: red'>#{error_message}</span>" if error_message

    color = status_category_color status

    visibility = ''
    if is_category == false && board.visible_columns.none? { |column| column.status_ids.include? status.id }
      visibility = icon_span(
        title: "Not visible: The status #{status.name.inspect} is not mapped to any column and will not be visible",
        icon: ' 👀'
      )
    end
    text = is_category ? status.category : status
    "<span title='Category: #{status.category}'>#{color_block color.name} #{text}</span>#{visibility}"
  end

  def icon_span title:, icon:
    "<span title='#{title}' style='font-size: 0.8em;'>#{icon}</span>"
  end

  def status_category_color status
    case status.category.key
    when 'new' then CssVariable['--status-category-todo-color']
    when 'indeterminate' then CssVariable['--status-category-inprogress-color']
    when 'done' then CssVariable['--status-category-done-color']
    else CssVariable['--status-category-unknown-color'] # Theoretically impossible but seen in prod.
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

  def color_block color, title: nil
    result = +''
    result << "<div class='color_block' style='"
    result << "background: #{CssVariable[color]};" if color
    result << 'visibility: hidden;' unless color
    result << "'"
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
