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
  def run
    sprints = sprints_in_time_range
    return nil if sprints.empty?

    result = String.new
    result << '<h1>Sprint Burndowns</h1>'

    sprints.sort_by(&:end_time).each do |sprint|
      result << "<h2>#{sprint.name}</h2>"
      result << "<div>#{sprint.goal}</div>" if sprint.goal

      result << process_one_sprint(sprint, use_story_points: true)
      # result << process_one_sprint(sprint, use_story_points: false)
    end

    result
  end

  # select all the changes that are relevant for the sprint. If this issue never appears in this sprint then return [].
  def single_issue_change_data issue, sprint
    story_points = nil
    ever_in_sprint = false
    change_data = []

    started_time = cycletime.started_time(issue)
    stopped_time = cycletime.stopped_time(issue)

    issue.changes.each do |change|
      action = nil
      value = nil

      if change.sprint? && change.value == sprint.name
        action = :enter_sprint
        ever_in_sprint = true
      elsif change.sprint? && change.old_value == sprint.name
        action = :leave_sprint
      elsif change.story_points?
        action = :story_points
        story_points = change.value.to_f || 0.0
        value = story_points - (change.old_value&.to_f || 0.0)
      elsif started_time && change.time == started_time
        started_time = nil
        action = :issue_started
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

  def process_one_sprint sprint, use_story_points:
    sprint_data = []
    issues.each do |issue|
      sprint_data += single_issue_change_data(issue, sprint)
    end
    sprint_data.sort_by!(&:time)

    starting_count, ending_count = end_posts_story_point_count data: sprint_data, sprint: sprint

    story_points = starting_count

    sprint_end_time = guess_sprint_end_time sprint, sprint_data
    sprint_time_range = sprint.start_time..sprint_end_time
    sprint_date_range = sprint.start_time.to_date..sprint_end_time.to_date

    data_set = []
    data_set << {
      y: starting_count,
      x: chart_format(sprint.start_time),
      title: 'First element'
    }
    sprint_data.each do |change_data|
      # puts change_data.inspect
      # next unless sprint_time_range.include? change_data.time
      next unless change_data.time >= sprint.start_time

      case change_data.action
      when :story_points
        story_points += change_data.value
      when :enter_sprint
        story_points += change_data.story_points
      when :issue_ended, :leave_spring
        story_points -= change_data.story_points
      end

      data_set << {
        y: story_points,
        x: chart_format(change_data.time),
        title: "#{change_data.issue.key} #{change_data.action}"
      }
    end

    if sprint.completed_time
      data_set << {
        y: ending_count,
        x: chart_format(sprint.completed_time),
        title: 'Last element'
      }
    end

    color = 'red'
    label = 'bar'
    data_sets = [{
      label: label,
      data: data_set,
      fill: false,
      showLine: true,
      borderColor: color,
      # lineTension: 0.4,
      backgroundColor: color
    }]

    render(binding, __FILE__)
  end

  def end_posts_story_point_count data:, sprint:
    starting_count = nil
    ending_count = nil

    story_point_count = 0.0
    data.each do |change_data|
      starting_count = story_point_count if starting_count.nil? && change_data.time >= sprint.start_time
      ending_count = story_point_count if ending_count.nil? && change_data.time >= sprint.end_time

      story_point_count += change_data.value if change_data.action == :story_points
    end
    [starting_count || story_point_count, ending_count || story_point_count]
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

