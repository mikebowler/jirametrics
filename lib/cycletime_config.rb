# frozen_string_literal: true

require './lib/self_or_issue_dispatcher'
require 'date'

class CycleTimeConfig
  include SelfOrIssueDispatcher

  def initialize parent_config:, label:, block:
    @parent_config = parent_config
    @label = label
    instance_eval(&block)
  end

  def start_at block = nil
    @start_at = block unless block.nil?
    @start_at
  end

  def stop_at block = nil
    @stop_at = block unless block.nil?
    @stop_at
  end

  def file_config
    @parent_config.file_config
  end

  def in_progress? issue
    started_time(issue) && stopped_time(issue).nil?
  end

  def done? issue
    stopped_time(issue)
  end

  def started_time issue
    @start_at.call(issue)
  end

  def stopped_time issue
    @stop_at.call(issue)
  end

  def cycletime issue
    start = started_time(issue)
    stop = stopped_time(issue)
    return nil if start.nil? || stop.nil?

    (stop - start).to_i + 1
  end

  def age issue
    start = started_time(issue)
    stop = Date.today
    return nil if start.nil? || stop.nil?

    (stop - start).to_i + 1
  end
end
