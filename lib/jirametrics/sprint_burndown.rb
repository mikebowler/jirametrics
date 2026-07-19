# frozen_string_literal: true

class SprintBurndown < ChartBase
  attr_reader :use_story_points, :use_story_counts, :summary_stats
  attr_accessor :board_id

  def initialize
    super

    @summary_stats = {}
    header_text 'Sprint burndown'
    description_text <<-TEXT
      <div class="p">
        Burndowns for all sprints in this time period. The different colours are only to
        differentiate one sprint from another as they may overlap time periods.
      </div>
      #{describe_non_working_days}
    TEXT
    @x_axis_title = 'Date'
    @y_axis_title = 'Items remaining'
  end

  def options= arg
    case arg
    when :points_only
      @use_story_points = true
      @use_story_counts = false
    when :counts_only
      @use_story_points = false
      @use_story_counts = true
    when :points_and_counts
      @use_story_points = true
      @use_story_counts = true
    else
      raise "Unexpected option: #{arg}"
    end
  end

  def run
    return nil unless current_board.scrum?

    sprints = sprints_in_time_range current_board

    change_data_by_sprint = {}
    sprints.each do |sprint|
      change_data = []
      issues.each do |issue|
        change_data += changes_for_one_issue(issue: issue, sprint: sprint)
      end
      change_data_by_sprint[sprint] = change_data.sort_by(&:time)
    end

    result = +''
    result << render_top_text(binding)

    possible_colours = (1..ChartBase::OKABE_ITO_PALETTE.size).collect { |i| CssVariable["--sprint-burndown-sprint-color-#{i}"] }
    charts_to_generate = []
    charts_to_generate << [:data_set_by_story_points, 'Story Points'] if @use_story_points
    charts_to_generate << [:data_set_by_story_counts, 'Story Count'] if @use_story_counts
    charts_to_generate.each do |data_method, y_axis_title|
      @summary_stats.clear
      data_sets = []
      sprints.each_with_index do |sprint, index|
        color = possible_colours[index % possible_colours.size]
        label = sprint.name
        data = send(data_method, sprint: sprint, change_data_for_sprint: change_data_by_sprint[sprint])
        data_sets << {
          label: label,
          data: data,
          fill: false,
          showLine: true,
          borderColor: color,
          backgroundColor: color,
          stepped: true,
          pointStyle: %w[rect circle] # First dot is visually different from the rest
        }
      end

      legend = []
      case data_method
      when :data_set_by_story_counts
        legend << '<b>Started</b>: Number of issues already in the sprint, when the sprint was started.'
        legend << '<b>Completed</b>: Number of issues, completed during the sprint'
        legend << '<b>Added</b>: Number of issues added in the middle of the sprint'
        legend << '<b>Removed</b>: Number of issues removed while the sprint was in progress'
      when :data_set_by_story_points
        legend << '<b>Started</b>: Total count of story points when the sprint was started'
        legend << '<b>Completed</b>: Count of story points completed during the sprint'
        legend << '<b>Added</b>: Count of story points added in the middle of the sprint'
        legend << '<b>Removed</b>: Count of story points removed while the sprint was in progress'
      else
        raise "Unexpected method #{data_method}"
      end

      result << render(binding, __FILE__)
    end

    result
  end

  def sprints_in_time_range board
    board.sprints.select do |sprint|
      # If it's never been started then it's just a holding area. Ignore it.
      next if sprint.future?

      sprint_end_time = sprint.completed_time || sprint.end_time
      sprint_start_time = sprint.start_time
      next false if sprint_start_time.nil?

      time_range.include?(sprint_start_time) || time_range.include?(sprint_end_time) ||
        (sprint_start_time < time_range.begin && sprint_end_time > time_range.end)
    end || []
  end

  # select all the changes that are relevant for the sprint. If this issue never appears in this sprint then return [].
  def changes_for_one_issue issue:, sprint:
    estimate = 0.0
    currently_in_sprint = false
    completed_has_been_tracked = false
    change_data = []

    estimate_display_name = current_board.estimation_configuration.display_name
    issue_completed_time = issue.started_stopped_times.last

    issue.changes.each do |change|
      action = nil
      value = nil

      if change.sprint?
        in_change_item = sprint_in_change_item(sprint, change)
        action, value = sprint_change_action(in_change_item, currently_in_sprint, estimate)
        currently_in_sprint = in_change_item
      elsif estimate_change_before_completion?(change, estimate_display_name, issue_completed_time)
        action = :story_points
        estimate = change.value.to_f
        value = estimate - change.old_value.to_f
      elsif reached_completion?(completed_has_been_tracked, change, issue_completed_time)
        completed_has_been_tracked = true
        action = :issue_stopped
        value = -estimate
      end

      next unless action

      change_data << SprintIssueChangeData.new(
        time: change.time, issue: issue, action: action, value: value, estimate: estimate
      )
    end

    ever_entered_sprint?(change_data) ? change_data : []
  end

  # Two sprint changes in a row can say the same thing, so an event only fires when the membership
  # actually flips: entering (was out, now in) or leaving (was in, now out).
  def sprint_change_action in_change_item, currently_in_sprint, estimate
    return [:enter_sprint, estimate] if currently_in_sprint == false && in_change_item
    return [:leave_sprint, -estimate] if currently_in_sprint && in_change_item == false

    [nil, nil]
  end

  def estimate_change_before_completion? change, estimate_display_name, issue_completed_time
    change.field == estimate_display_name && (issue_completed_time.nil? || change.time < issue_completed_time)
  end

  def reached_completion? completed_has_been_tracked, change, issue_completed_time
    completed_has_been_tracked == false && change.time == issue_completed_time
  end

  def ever_entered_sprint? change_data
    change_data.any? { |data| data.action == :enter_sprint }
  end

  def sprint_in_change_item sprint, change_item
    change_item.raw['to'].split(/\s*,\s*/).any? { |id| id.to_i == sprint.id }
  end

  def data_set_by_story_points sprint:, change_data_for_sprint:
    build_sprint_data_set(
      sprint: sprint, change_data_for_sprint: change_data_for_sprint, measure: SprintPointsMeasure.new
    )
  end

  def data_set_by_story_counts sprint:, change_data_for_sprint:
    build_sprint_data_set(
      sprint: sprint, change_data_for_sprint: change_data_for_sprint, measure: SprintCountMeasure.new
    )
  end

  # Walks the sprint's change stream once. The measure decides how each change accumulates and reads
  # out; the loop structure is shared by both the story-points and story-counts views.
  def build_sprint_data_set sprint:, change_data_for_sprint:, measure:
    data_set = []
    start_written = false

    change_data_for_sprint.each do |change_data|
      if start_pending?(start_written, change_data, sprint)
        data_set << sprint_start_point(measure, sprint)
        start_written = true
      end
      break if past_sprint_end?(change_data, sprint)

      measure.update_state change_data
      next unless change_data.time >= sprint.start_time

      message = measure.record change_data
      data_set << change_point(measure, change_data, message) if message
    end

    append_closing_points data_set, measure, sprint, start_written
    @summary_stats[sprint] = measure.summary_stats
    data_set
  end

  def start_pending? start_written, change_data, sprint
    !start_written && change_data.time >= sprint.start_time
  end

  def past_sprint_end? change_data, sprint
    sprint.completed_time && change_data.time > sprint.completed_time
  end

  def sprint_start_point measure, sprint
    measure.summary_stats.started = measure.value
    { y: measure.value, x: chart_format(sprint.start_time), title: measure.started_title }
  end

  def change_point measure, change_data, message
    { y: measure.value, x: chart_format(change_data.time), title: "#{change_data.issue.key} #{message}" }
  end

  def append_closing_points data_set, measure, sprint, start_written
    # Nothing in the change stream triggered the sprint-start marker, so write it now.
    data_set << sprint_start_point(measure, sprint) unless start_written

    if sprint.completed_time
      data_set << { y: measure.value, x: chart_format(sprint.completed_time), title: measure.ended_title }
      measure.summary_stats.remaining = measure.value
    end
    return if sprint.completed_at?(time_range.end)

    data_set << { y: measure.value, x: chart_format(time_range.end), title: measure.active_title }
  end
end
