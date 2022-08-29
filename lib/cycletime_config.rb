# frozen_string_literal: true

require './lib/self_or_issue_dispatcher'
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

    (stop.to_date - start.to_date).to_i + 1
  end

  def age issue, today: nil
    start = started_time(issue)
    stop = today || @today || Date.today
    return nil if start.nil? || stop.nil?

    (stop.to_date - start.to_date).to_i + 1
  end

  def possible_statuses
    parent_config.file_config.project_config.possible_statuses
  end
end
