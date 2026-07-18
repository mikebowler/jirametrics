# frozen_string_literal: true

# The roll-up numbers for a single sprint's burndown: how many points/issues the sprint started
# with, how many were added/removed/completed while it ran, and how many remained at the end.
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
