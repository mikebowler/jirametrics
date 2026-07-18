# frozen_string_literal: true

# The story-points view of a sprint burndown: a running total of estimate as issues enter, leave,
# complete, or have their points changed. It plugs into SprintBurndown#build_sprint_data_set, which
# shares its loop with the story-count view (SprintCountMeasure).
class SprintPointsMeasure
  attr_reader :summary_stats

  def initialize
    @summary_stats = SprintSummaryStats.new
    @summary_stats.completed = 0.0
    @estimate = 0.0
    @issues_currently_in_sprint = []
  end

  def value = @estimate

  def update_state change_data
    case change_data.action
    when :enter_sprint
      @issues_currently_in_sprint << change_data.issue.key
      @estimate += change_data.estimate
    when :leave_sprint
      @issues_currently_in_sprint.delete change_data.issue.key
      @estimate -= change_data.estimate
    when :story_points
      @estimate += change_data.value if @issues_currently_in_sprint.include? change_data.issue.key
    end
  end

  def record change_data
    case change_data.action
    when :story_points
      return nil unless @issues_currently_in_sprint.include? change_data.issue.key

      @summary_stats.points_values_changed = true
      old_estimate = change_data.estimate - change_data.value
      "Story points changed from #{old_estimate} points to #{change_data.estimate} points"
    when :enter_sprint
      @summary_stats.added += change_data.estimate
      "Added to sprint with #{points_label change_data.estimate}"
    when :issue_stopped
      @estimate -= change_data.estimate
      @issues_currently_in_sprint.delete change_data.issue.key
      @summary_stats.completed += change_data.estimate
      "Completed with #{points_label change_data.estimate}"
    when :leave_sprint
      @summary_stats.removed += change_data.estimate
      "Removed from sprint with #{points_label change_data.estimate}"
    else
      raise "Unexpected action: #{change_data.action}"
    end
  end

  def points_label estimate
    "#{estimate || 'no'} points"
  end

  def started_title = "Sprint started with #{@estimate} points"
  def ended_title = "Sprint ended with #{@estimate} points unfinished"
  def active_title = "Sprint still active. #{@estimate} points still in progress."
end
