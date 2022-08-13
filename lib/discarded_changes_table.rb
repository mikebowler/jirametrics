# frozen_string_literal: true

require './lib/chart_base'
require './lib/daily_chart_item_generator'

class DiscardedChangesTable < ChartBase
  attr_accessor :issues, :cycletime, :possible_statuses, :date_range

  def initialize original_issue_times
    super()
    @original_issue_times = original_issue_times
  end

  def run
    messages = []

    @original_issue_times.each do |issue, hash|
      new_start_time = @cycletime.started_time(issue)
      old_start_time = hash[:started_time]

      # If it didn't change the start time then we don't really care.
      next if new_start_time == old_start_time

      cutoff_time = hash[:cutoff_time]
      stop_time = @cycletime.stopped_time(issue)

      # This is a stopped but never started item. Nothing useful we can say about this.
      next if stop_time && new_start_time.nil?

      old_start_date = old_start_time.to_date
      new_start_date = new_start_time&.to_date

      cutoff_date = cutoff_time.to_date

      message = String.new

      days_ignored = nil
      if stop_time.nil? && new_start_time.nil?
        days_ignored = (cutoff_date - old_start_date).to_i + 1
        message << "Started on #{old_start_date} and then moved back to 'not started' "
        message << "on #{cutoff_date}."
      else
        message << "Started on #{old_start_date} and now showing started again on #{new_start_date}. "
        if stop_time.nil? && new_start_time
          old_age = (date_range.end - old_start_date).to_i + 1
          new_age = (date_range.end - new_start_date).to_i + 1
          message << "The current age of this item now shows as #{label_days new_age} when it should really "
          message << "be #{label_days old_age}"
          days_ignored = old_age - new_age
        else
          stop_date = stop_time.to_date

          old_cycletime = (stop_date - old_start_date).to_i + 1
          new_cycletime = (stop_date - new_start_date).to_i + 1
          message << "The current age of this item now shows as #{label_days new_cycletime} when it should really "
          message << "be #{label_days old_cycletime}"
          days_ignored = old_cycletime - new_cycletime
        end
      end

      # If days_ignored is zero then we don't really care
      messages << [issue, days_ignored, message] unless days_ignored.zero?
    end

    messages.sort_by! { |a| a[0].key_as_i }
    render(binding, __FILE__) unless messages.empty?
  end
end

