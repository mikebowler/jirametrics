# frozen_string_literal: true

require './lib/self_or_issue_dispatcher'

class CycleTimeConfig
  include SelfOrIssueDispatcher

  def initialize parent_config:, label:, block:
    @parent_config = parent_config
    @label = label
    instance_eval(&block)
  end

  def start_at block
    @start_at = block unless block.nil?
    @start_at
  end

  def stop_at block
    @stop_at = block unless block.nil?
    @stop_at
  end
end
