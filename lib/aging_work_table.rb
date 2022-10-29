# frozen_string_literal: true

require './lib/chart_base'

class AgingWorkTable < ChartBase
  attr_accessor :today, :board_id

  def initialize expedited_priority_name, block
    super()
    @expedited_priority_name = expedited_priority_name
    @blocked_icon = '🛑'
    @expedited_icon = '🔥'
    @stalled_icon = '🟧'
    @stalled_threshold = 5
    @age_cutoff = 0

    instance_eval(&block) if block
  end

  def run
    @today = date_range.end
    aging_issues = select_aging_issues

    expedited_but_not_started = @issues.select do |issue|
      cycletime = issue.board.cycletime
      cycletime.started_time(issue).nil? && cycletime.stopped_time(issue).nil? && expedited?(issue)
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
      next true if issue.blocked_on_date?(@today) || expedited?(issue)

      age = (@today - started.to_date).to_i + 1
      age > @age_cutoff
    end
    @any_scrum_boards = aging_issues.any? { |issue| issue.board.scrum? }
    aging_issues.sort { |a, b| b.board.cycletime.age(b, today: @today) <=> a.board.cycletime.age(a, today: @today) }
  end

  def expedited? issue
    issue.raw['fields']['priority']['name'] == @expedited_priority_name
  end

  def icon_span title:, icon:
    "<span title='#{title}' style='font-size: 0.8em;'>#{icon}</span>"
  end

  def expedited_text issue
    return unless expedited?(issue)

    icon_span(title: "Expedited: Has a priority of &quot;#{@expedited_priority_name}&quot;", icon: @expedited_icon)
  end

  def blocked_text issue
    if issue.blocked_on_date? @today
      icon_span title: 'Blocked: Has the flag set', icon: @blocked_icon
    elsif issue.stalled_on_date?(@today, @stalled_threshold) && issue.board.cycletime.started_time(issue)
      icon_span(
        title: "Stalled: Hasn&apos;t had any activity in #{@stalled_threshold} days and isn&apos;t explicitly " \
          'marked as blocked',
        icon: @stalled_icon
      )
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
    sprints = issue.board.sprints

    issue.changes.each do |change|
      next unless change.sprint?

      sprint_ids << change.raw['to'].split(/\s*,\s*/).collect { |id| id.to_i }
    end
    sprint_ids.flatten!

    sprints.select { |s| sprint_ids.include? s.id }.collect do |sprint|
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
end
