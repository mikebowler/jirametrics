# frozen_string_literal: true

require 'jirametrics/self_or_issue_dispatcher'
require 'date'

class CycleTimeConfig
  include SelfOrIssueDispatcher

  attr_reader :label, :settings, :file_system

  def initialize possible_statuses:, label:, block:, settings:, file_system: nil, today: Date.today
    @possible_statuses = possible_statuses
    @label = label
    @today = today
    @settings = settings

    # If we hit something deprecated and this is nil then we'll blow up. Although it's ugly, this
    # may make it easier to find problems in the test code ;-)
    @file_system = file_system
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

  def fabricate_change_item time
    @file_system.deprecated(
      date: '2024-12-16', message: "This method should now return a ChangeItem not a #{time.class}", depth: 4
    )
    raw = {
      'field' => 'Fabricated change',
      'to' => '0',
      'toString' => '',
      'from' => '0',
      'fromString' => ''
    }
    ChangeItem.new raw: raw, time: time, artificial: true, author_raw: nil
  end

  def started_stopped_changes issue
    cache_key = "#{issue.key}:#{issue.board.id}"
    last_result = (@cache ||= {})[cache_key]
    return *last_result if last_result && settings['cache_cycletime_calculations']

    started = resolve_change(@start_at, issue)
    stopped = resolve_change(@stop_at, issue)
    started = collapse_zero_length_start(started, stopped)

    result = [started, stopped]
    warn_on_cache_mismatch(issue: issue, result: result, last_result: last_result)
    @cache[cache_key] = result
    result
  end

  # start_at/stop_at blocks should return a ChangeItem or nil. Older configs may instead return false
  # (meaning "not found") or a bare Time; normalize both of those legacy forms to a ChangeItem or nil.
  def resolve_change block, issue
    change = block.call(issue)
    change ||= nil
    change = fabricate_change_item(change) if !change.nil? && !change.is_a?(ChangeItem)
    change
  end

  # When start and stop land on the same instant, treat the issue as stopped-but-never-started so a
  # zero-length span doesn't conflict with 'in or right of' start logic.
  def collapse_zero_length_start started, stopped
    return nil if started&.time == stopped&.time

    started
  end

  def warn_on_cache_mismatch issue:, result:, last_result:
    return unless last_result && result != last_result

    @file_system.error(
      "Calculation mismatch; this could break caching. #{issue.inspect} new=#{result.inspect}, " \
        "previous=#{last_result.inspect}"
    )
  end

  def started_stopped_times issue
    started, stopped = started_stopped_changes(issue)
    [started&.time, stopped&.time]
  end

  def flush_cache
    @cache = nil
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
