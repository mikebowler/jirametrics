# frozen_string_literal: true

require 'jirametrics/chart_base'

class AgingWorkTable < ChartBase
  attr_accessor :today, :board_id

  def initialize block
    super()
    @blocked_icon = '🛑'
    @expedited_icon = '🔥'
    @stalled_icon = '🟧'
    @stalled_threshold = 5
    @dead_icon = '⬛'
    @dead_threshold = 45
    @age_cutoff = 0

    instance_eval(&block) if block
  end

  def run
    @today = date_range.end
    aging_issues = select_aging_issues

    expedited_but_not_started = @issues.select do |issue|
      cycletime = issue.board.cycletime
      cycletime.started_time(issue).nil? && cycletime.stopped_time(issue).nil? && issue.expedited?
    end
    aging_issues += expedited_but_not_started.sort_by(&:created)

    render(binding, __FILE__)
  end

  def select_aging_issues
    aging_issues = @issues.select do |issue|
      cycletime = issue.board.cycletime
      started = cycletime.started_time(issue)
      stopped = cycletime.stopped_time(issue)
      next false if started.nil? || stopped
      next true if issue.blocked_on_date?(@today, end_time: time_range.end) || issue.expedited?

      age = (@today - started.to_date).to_i + 1
      age > @age_cutoff
    end
    @any_scrum_boards = aging_issues.any? { |issue| issue.board.scrum? }
    aging_issues.sort { |a, b| b.board.cycletime.age(b, today: @today) <=> a.board.cycletime.age(a, today: @today) }
  end

  def icon_span title:, icon:
    "<span title='#{title}' style='font-size: 0.8em;'>#{icon}</span>"
  end

  def expedited_text issue
    return unless issue.expedited?

    name = issue.raw['fields']['priority']['name']
    icon_span(title: "Expedited: Has a priority of &quot;#{name}&quot;", icon: @expedited_icon)
  end

  def blocked_text issue
    started_time = issue.board.cycletime.started_time(issue)
    return nil if started_time.nil?

    current = issue.blocked_stalled_changes(end_time: time_range.end)[-1]
    if current.blocked?
      icon_span title: current.reasons, icon: @blocked_icon
    elsif current.stalled?
      if current.stalled_days && current.stalled_days > @dead_threshold
        icon_span(
          title: "Dead? Hasn&apos;t had any activity in #{label_days current.stalled_days}. " \
            'Does anyone still care about this?',
          icon: @dead_icon
        )
      else
        icon_span(
          title: current.reasons,
          icon: @stalled_icon
        )
      end
    end
  end

  def unmapped_status_text issue
    icon_span(
      title: "The status #{issue.status.name.inspect} is not mapped to any column and will not be visible",
      icon: ' ⁉️'
    )
  end

  def fix_versions_text issue
    issue.fix_versions.collect do |fix|
      if fix.released?
        icon_text = icon_span title: 'Released. Likely not on the board anymore.', icon: '✅'
        "#{fix.name} #{icon_text}"
      else
        fix.name
      end
    end.join('<br />')
  end

  def sprints_text issue
    sprint_ids = []

    issue.changes.each do |change|
      next unless change.sprint?

      sprint_ids << change.raw['to'].split(/\s*,\s*/).collect { |id| id.to_i }
    end
    sprint_ids.flatten!

    issue.board.sprints.select { |s| sprint_ids.include? s.id }.collect do |sprint|
      icon_text = nil
      if sprint.active?
        icon_text = icon_span title: 'Active sprint', icon: '➡️'
      else
        icon_text = icon_span title: 'Sprint closed', icon: '✅'
      end
      "#{sprint.name} #{icon_text}"
    end.join('<br />')
  end

  def current_status_visible? issue
    issue.board.visible_columns.any? { |column| column.status_ids.include? issue.status.id }
  end

  def age_cutoff age = nil
    @age_cutoff = age.to_i if age
    @age_cutoff
  end

  def any_scrum_boards?
    @any_scrum_boards
  end

  def parent_hierarchy issue
    result = []

    while issue
      cyclical_parent_links = result.include? issue
      result << issue

      break if cyclical_parent_links

      issue = issue.parent
    end

    result.reverse
  end
end
