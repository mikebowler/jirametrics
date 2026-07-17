# frozen_string_literal: true

# Rolls a stream of BlockedStalledChange entries up into a single winning entry per date across
# the requested date range. It's handed the already-computed stream so it never reaches back
# through the issue's collaborators.
class BlockedStalledByDateBuilder
  def initialize blocked_stalled_changes:, date_range:
    @blocked_stalled_changes = blocked_stalled_changes
    @date_range = date_range
  end

  def build
    results = winners_and_last_by_date
    fill_gaps results
    results = results.transform_values(&:first)
    extrapolate_across_range results

    # We've been accumulating data for every date to keep the code simple. Now drop anything
    # that isn't in the requested date_range.
    results.select! { |date, _value| @date_range.include? date }
    results
  end

  # For each date we track both the winning change (the one that best represents the day) and the
  # last change seen (used to carry state forward into days that had no changes of their own).
  def winners_and_last_by_date
    results = {}
    @blocked_stalled_changes.each do |change|
      date = change.time.to_date
      winning_change, = results[date]
      winning_change = change if winning_change.nil? || wins_the_day?(change, winning_change)
      results[date] = [winning_change, change]
    end
    results
  end

  def wins_the_day? change, winning_change
    change.blocked? ||
      (change.active? && (winning_change.active? || winning_change.stalled?)) ||
      (change.stalled? && winning_change.stalled?)
  end

  def fill_gaps results
    last_populated_date = nil
    (results.keys.min..results.keys.max).each do |date|
      if results.key? date
        last_populated_date = date
      else
        _winner, last = results[last_populated_date]
        results[date] = [last, last]
      end
    end
  end

  def extrapolate_across_range results
    # The requested date range may span outside the actual changes we find in the changelog.
    date_of_first_change = @blocked_stalled_changes[0].time.to_date
    date_of_last_change = @blocked_stalled_changes[-1].time.to_date
    @date_range.each do |date|
      results[date] = @blocked_stalled_changes[0] if date < date_of_first_change
      results[date] = @blocked_stalled_changes[-1] if date > date_of_last_change
    end
  end
end
