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

  def started_stopped_times issue
    started = @start_at.call(issue)
    stopped = @stop_at.call(issue)

    # In the case where started and stopped are exactly the same time, we pretend that
    # it just stopped and never started. This allows us to have logic like 'in or right of'
    # for the start and not have it conflict.
    started = nil if started == stopped

    [started, stopped]
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
