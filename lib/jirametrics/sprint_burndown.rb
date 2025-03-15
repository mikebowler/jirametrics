# frozen_string_literal: true

class SprintSummaryStats
  attr_accessor :started, :added, :changed, :removed, :completed, :remaining, :points_values_changed

  def initialize
    @added = 0
    @completed = 0
    @removed = 0
    @started = 0
    @remaining = 0
    @points_values_changed = false
  end
end

class SprintBurndown < ChartBase
  attr_reader :use_story_points, :use_story_counts
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
    sprints = sprints_in_time_range all_boards[board_id]
    return nil if sprints.empty?

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

    possible_colours = (1..5).collect { |i| CssVariable["--sprint-burndown-sprint-color-#{i}"] }
    charts_to_generate = []
    charts_to_generate << [:data_set_by_story_points, 'Story Points'] if @use_story_points
    charts_to_generate << [:data_set_by_story_counts, 'Story Count'] if @use_story_counts
    charts_to_generate.each do |data_method, y_axis_title| # rubocop:disable Style/HashEachMethods
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
    ever_in_sprint = false
    currently_in_sprint = false
    change_data = []

    estimate_display_name = current_board.estimation_configuration.display_name

    issue_completed_time = issue.board.cycletime.started_stopped_times(issue).last
    completed_has_been_tracked = false

    issue.changes.each do |change|
      action = nil
      value = nil

      if change.sprint?
        # We can get two sprint changes in a row that tell us the same thing so we have to verify
        # that something actually changed.
        in_change_item = sprint_in_change_item(sprint, change)
        if currently_in_sprint == false && in_change_item
          action = :enter_sprint
          ever_in_sprint = true
          value = estimate
        elsif currently_in_sprint && in_change_item == false
          action = :leave_sprint
          value = -estimate
        end
        currently_in_sprint = in_change_item
      elsif change.field == estimate_display_name && (issue_completed_time.nil? || change.time < issue_completed_time)
        action = :story_points
        estimate = change.value.to_f
        value = estimate - change.old_value.to_f
      elsif completed_has_been_tracked == false && change.time == issue_completed_time
        completed_has_been_tracked = true
        action = :issue_stopped
        value = -estimate
      end

      next unless action

      change_data << SprintIssueChangeData.new(
        time: change.time, issue: issue, action: action, value: value, story_points: estimate
      )
    end

    return [] unless ever_in_sprint

    change_data
  end

  def sprint_in_change_item sprint, change_item
    change_item.raw['to'].split(/\s*,\s*/).any? { |id| id.to_i == sprint.id }
  end

  def data_set_by_story_points sprint:, change_data_for_sprint: # rubocop:disable Metrics/CyclomaticComplexity
    summary_stats = SprintSummaryStats.new
    summary_stats.completed = 0.0

    story_points = 0.0
    start_data_written = false
    data_set = []

    issues_currently_in_sprint = []

    change_data_for_sprint.each do |change_data|
      if start_data_written == false && change_data.time >= sprint.start_time
        data_set << {
          y: story_points,
          x: chart_format(sprint.start_time),
          title: "Sprint started with #{story_points} points"
        }
        summary_stats.started = story_points
        start_data_written = true
      end

      break if sprint.completed_time && change_data.time > sprint.completed_time

      case change_data.action
      when :enter_sprint
        issues_currently_in_sprint << change_data.issue.key
        story_points += change_data.story_points
      when :leave_sprint
        issues_currently_in_sprint.delete change_data.issue.key
        story_points -= change_data.story_points
      when :story_points
        story_points += change_data.value if issues_currently_in_sprint.include? change_data.issue.key
      end

      next unless change_data.time >= sprint.start_time

      message = nil
      case change_data.action
      when :story_points
        next unless issues_currently_in_sprint.include? change_data.issue.key

        old_story_points = change_data.story_points - change_data.value
        message = "Story points changed from #{old_story_points} points to #{change_data.story_points} points"
        summary_stats.points_values_changed = true
      when :enter_sprint
        message = "Added to sprint with #{change_data.story_points || 'no'} points"
        summary_stats.added += change_data.story_points
      when :issue_stopped
        story_points -= change_data.story_points
        message = "Completed with #{change_data.story_points || 'no'} points"
        issues_currently_in_sprint.delete change_data.issue.key
        summary_stats.completed += change_data.story_points
      when :leave_sprint
        message = "Removed from sprint with #{change_data.story_points || 'no'} points"
        summary_stats.removed += change_data.story_points
      else
        raise "Unexpected action: #{change_data.action}"
      end

      data_set << {
        y: story_points,
        x: chart_format(change_data.time),
        title: "#{change_data.issue.key} #{message}"
      }
    end

    unless start_data_written
      # There was nothing that triggered us to write the sprint started block so do it now.
      data_set << {
        y: story_points,
        x: chart_format(sprint.start_time),
        title: "Sprint started with #{story_points} points"
      }
      summary_stats.started = story_points
    end

    if sprint.completed_time
      data_set << {
        y: story_points,
        x: chart_format(sprint.completed_time),
        title: "Sprint ended with #{story_points} points unfinished"
      }
      summary_stats.remaining = story_points
    end

    unless sprint.completed_at?(time_range.end)
      data_set << {
        y: story_points,
        x: chart_format(time_range.end),
        title: "Sprint still active. #{story_points} points still in progress."
      }
    end

    @summary_stats[sprint] = summary_stats
    data_set
  end

  def data_set_by_story_counts sprint:, change_data_for_sprint:
    summary_stats = SprintSummaryStats.new

    data_set = []
    issues_currently_in_sprint = []
    start_data_written = false

    change_data_for_sprint.each do |change_data|
      if start_data_written == false && change_data.time >= sprint.start_time
        data_set << {
          y: issues_currently_in_sprint.size,
          x: chart_format(sprint.start_time),
          title: "Sprint started with #{issues_currently_in_sprint.size} stories"
        }
        summary_stats.started = issues_currently_in_sprint.size
        start_data_written = true
      end

      break if sprint.completed_time && change_data.time > sprint.completed_time

      case change_data.action
      when :enter_sprint
        issues_currently_in_sprint << change_data.issue.key
      when :leave_sprint, :issue_stopped
        issues_currently_in_sprint.delete change_data.issue.key
      end

      next unless change_data.time >= sprint.start_time

      message = nil
      case change_data.action
      when :enter_sprint
        message = 'Added to sprint'
        summary_stats.added += 1
      when :issue_stopped
        message = 'Completed'
        summary_stats.completed += 1
      when :leave_sprint
        message = 'Removed from sprint'
        summary_stats.removed += 1
      end

      next unless message

      data_set << {
        y: issues_currently_in_sprint.size,
        x: chart_format(change_data.time),
        title: "#{change_data.issue.key} #{message}"
      }
    end

    unless start_data_written
      # There was nothing that triggered us to write the sprint started block so do it now.
      data_set << {
        y: issues_currently_in_sprint.size,
        x: chart_format(sprint.start_time),
        title: "Sprint started with #{issues_currently_in_sprint.size || 'no'} stories"
      }
    end

    if sprint.completed_time
      data_set << {
        y: issues_currently_in_sprint.size,
        x: chart_format(sprint.completed_time),
        title: "Sprint ended with #{issues_currently_in_sprint.size} stories unfinished"
      }
      summary_stats.remaining = issues_currently_in_sprint.size
    end

    unless sprint.completed_at?(time_range.end)
      # If the sprint is still active then we draw one final line to the end of the time range
      data_set << {
        y: issues_currently_in_sprint.size,
        x: chart_format(time_range.end),
        title: "Sprint still active. #{issues_currently_in_sprint.size} issues in progress."
      }
    end

    @summary_stats[sprint] = summary_stats
    data_set
  end
end
