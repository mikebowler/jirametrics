# frozen_string_literal: true

class SprintIssueChangeData
  attr_reader :time, :action, :value, :issue, :story_points

  def initialize time:, action:, value:, issue:, story_points:
    @time = time
    @action = action
    @value = value
    @issue = issue
    @story_points = story_points
  end

  def eql?(other)
    (other.class == self.class) && (other.state == state)
  end

  def state
    instance_variables.map { |variable| instance_variable_get variable }
  end
end

class SprintBurndown < ChartBase
  attr_accessor :use_story_points

  def initialize
    super()
    @use_story_points = true
  end

  def run
    sprints = sprints_in_time_range
    return nil if sprints.empty?

    data_sets = []
    sprints.each_with_index do |sprint, index|
      color = %w[blue orange green red brown][index % 5]
      label = sprint.name
      data_sets << {
        label: label,
        data: process_one_sprint(sprint),
        fill: false,
        showLine: true,
        borderColor: color,
        backgroundColor: color,
        stepped: true,
        pointStyle: %w[rect circle] # First dot is visually different from the rest
      }
    end

    render(binding, __FILE__)
  end

  # select all the changes that are relevant for the sprint. If this issue never appears in this sprint then return [].
  def single_issue_change_data issue:, sprint:
    story_points = nil
    ever_in_sprint = false
    change_data = []

    # TODO: It's ugly that we have both stopped_time and issue_stopped time. Change to use a flag rather
    # than clearing the time value.
    started_time = cycletime.started_time(issue)
    stopped_time = cycletime.stopped_time(issue)
    issue_stopped_time = stopped_time

    issue.changes.each do |change|
      action = nil
      value = nil

      if change.sprint? && change.value == sprint.name
        action = :enter_sprint
        ever_in_sprint = true
      elsif change.sprint? && change.old_value == sprint.name
        action = :leave_sprint
      elsif change.story_points? && (issue_stopped_time.nil? || change.time < issue_stopped_time)
        action = :story_points
        story_points = change.value.to_f || 0.0
        story_points = 1.0 unless use_story_points
        value = story_points - (change.old_value&.to_f || 0.0)
      elsif started_time && change.time == started_time
        started_time = nil
        # action = :issue_started
      elsif stopped_time && change.time == stopped_time
        stopped_time = nil
        action = :issue_stopped
        story_points = 0.0
      end

      next unless action

      change_data << SprintIssueChangeData.new(
        time: change.time, issue: issue, action: action, value: value, story_points: story_points
      )
    end

    return [] unless ever_in_sprint

    change_data
  end

  def process_one_sprint sprint
    sprint_data = []
    issues.each do |issue|
      sprint_data += single_issue_change_data(issue: issue, sprint: sprint)
    end
    sprint_data.sort_by!(&:time)

    story_points = starting_story_point_count data: sprint_data, sprint: sprint

    data_set = []
    data_set << {
      y: story_points,
      x: chart_format(sprint.start_time),
      title: "Sprint started with #{story_points}pts"
    }

    sprint_data.each do |change_data|
      next unless change_data.time >= sprint.start_time
      next if sprint.completed_time && change_data.time > sprint.completed_time

      message = nil
      case change_data.action
      when :story_points
        story_points += change_data.value
        old_story_points = change_data.story_points - change_data.value
        message = "Story points changed from #{old_story_points}pts to #{change_data.story_points}pts"
      when :enter_sprint
        story_points += change_data.story_points if change_data.story_points
        message = "Added to sprint with #{change_data.story_points || 'no'} points"
      when :issue_stopped
        story_points -= change_data.story_points if change_data.story_points
        message = "Completed with #{change_data.story_points || 'no'} points"
      when :leave_sprint
        story_points -= change_data.story_points if change_data.story_points
        message = "Removed from sprint with #{change_data.story_points || 'no'} points"
      else
        raise "Unexpected action: #{change_data.action}"
      end

      data_set << {
        y: story_points,
        x: chart_format(change_data.time),
        title: "#{change_data.issue.key} #{message}"
      }
    end

    if sprint.completed_time
      data_set << {
        y: story_points,
        x: chart_format(sprint.completed_time),
        title: 'Last element'
      }
    end

    data_set
  end

  def starting_story_point_count data:, sprint:
    starting_count = nil

    story_point_count = 0.0
    data.each do |change_data|
      starting_count = story_point_count if starting_count.nil? && change_data.time >= sprint.start_time
      story_point_count += change_data.value if change_data.action == :story_points
    end
    starting_count || story_point_count
  end

  def guess_sprint_end_time sprint, sprint_data
    # If the sprint is closed then we'll have an actual completed time. If it's still active then
    # in theory we should be using the endTime but the sprint may still be open past the time
    # that Jira thought it should have closed. So if we're past that defined end time then use
    # the time of the most recent activity because when the sprint is finally closed, the end
    # will certainly be later than that.
    #
    # Of course there's no guarantee that the sprint will have a most recent change as it may have
    # just been created. Sigh.
    time = sprint.completed_time
    return time if time

    most_recent_activity = sprint_data[-1]&.time
    anticipated_sprint_end = sprint.end_time

    # The sprint has been created but nothings been done with it.
    return anticipated_sprint_end if most_recent_activity.nil?

    if most_recent_activity > anticipated_sprint_end
      most_recent_activity
    else
      anticipated_sprint_end
    end
  end
end

