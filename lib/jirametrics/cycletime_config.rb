# frozen_string_literal: true

require 'jirametrics/self_or_issue_dispatcher'
require 'date'

class CycleTimeConfig
  include SelfOrIssueDispatcher

  attr_reader :label, :parent_config

  def initialize parent_config:, label:, block:, today: Date.today
    @parent_config = parent_config
    @label = label
    @today = today
    instance_eval(&block) unless block.nil?
  end

  def start_at block = nil
    @start_at = block unless block.nil?
    @start_at
  end

  def stop_at block = nil
    @stop_at = block unless block.nil?
    @stop_at
  end

  def in_progress? issue
    started_time, stopped_time = started_stopped_times(issue)
    started_time && stopped_time.nil?
  end

  def done? issue
    started_stopped_times(issue).last
  end

  def started_time issue
    deprecated date: '2024-10-16', message: 'Use started_stopped_times() instead'
    started_stopped_times(issue).first
  end

  def stopped_time issue
    deprecated date: '2024-10-16', message: 'Use started_stopped_times() instead'
    started_stopped_times(issue).last
  end

  def fabricate_change_item time
    deprecated date: '2024-12-16', message: 'This method should now return a ChangeItem not a Time', depth: 4
    raw = {
      'field' => 'Fabricated change',
      'to' => '0',
      'toString' => '',
      'from' => '0',
      'fromString' => ''
    }
    ChangeItem.new raw: raw, time: time, author: 'unknown', artificial: true
  end

  def started_stopped_changes issue
    started = @start_at.call(issue)
    stopped = @stop_at.call(issue)

    # Obscure edge case where some of the start_at and stop_at blocks might return false in place of nil.
    started = nil unless started
    stopped = nil unless stopped

    # These are only here for backwards compatibility. Hopefully nobody will ever need them.
    started = fabricate_change_item(started) if !started.nil? && !started.is_a?(ChangeItem)
    stopped = fabricate_change_item(stopped) if !stopped.nil? && !stopped.is_a?(ChangeItem)

    # In the case where started and stopped are exactly the same time, we pretend that
    # it just stopped and never started. This allows us to have logic like 'in or right of'
    # for the start and not have it conflict.
    started = nil if started&.time == stopped&.time

    [started, stopped]
  end

  def started_stopped_times issue
    started, stopped = started_stopped_changes(issue)
    [started&.time, stopped&.time]
  end

  def started_stopped_dates issue
    started_time, stopped_time = started_stopped_times(issue)
    [started_time&.to_date, stopped_time&.to_date]
  end

  def cycletime issue
    start, stop = started_stopped_times(issue)
    return nil if start.nil? || stop.nil?

    (stop.to_date - start.to_date).to_i + 1
  end

  def age issue, today: nil
    start = started_stopped_times(issue).first
    stop = today || @today || Date.today
    return nil if start.nil? || stop.nil?

    (stop.to_date - start.to_date).to_i + 1
  end

  def possible_statuses
    if parent_config.is_a? BoardConfig
      project_config = parent_config.project_config
    else
      # TODO: This will go away when cycletimes are no longer supported inside html_reports
      project_config = parent_config.file_config.project_config
    end
    project_config.possible_statuses
  end
end
