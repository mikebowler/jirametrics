# frozen_string_literal: true

# The story-count view of a sprint burndown: simply how many issues are in the sprint at any point.
# It plugs into SprintBurndown#build_sprint_data_set, which shares its loop with the story-points
# view (SprintPointsMeasure).
class SprintCountMeasure
  attr_reader :summary_stats

  def initialize
    @summary_stats = SprintSummaryStats.new
    @issues_currently_in_sprint = []
  end

  def value = @issues_currently_in_sprint.size

  def update_state change_data
    case change_data.action
    when :enter_sprint
      @issues_currently_in_sprint << change_data.issue.key
    when :leave_sprint, :issue_stopped
      @issues_currently_in_sprint.delete change_data.issue.key
    end
  end

  def record change_data
    case change_data.action
    when :enter_sprint
      @summary_stats.added += 1
      'Added to sprint'
    when :issue_stopped
      @summary_stats.completed += 1
      'Completed'
    when :leave_sprint
      @summary_stats.removed += 1
      'Removed from sprint'
    end
  end

  def started_title = "Sprint started with #{value} stories"
  def ended_title = "Sprint ended with #{value} stories unfinished"
  def active_title = "Sprint still active. #{value} issues in progress."
  def records_started_when_unwritten? = false
end
