# frozen_string_literal: true

module DiscardChangesBefore
  def discard_changes_before status_becomes: nil, &block
    if status_becomes
      status_becomes = [status_becomes] unless status_becomes.is_a? Array

      block = lambda do |issue|
        trigger_statuses = status_becomes.collect do |status_name|
          if status_name == :backlog
            issue.board.backlog_statuses.collect(&:name)
          else
            status_name
          end
        end.flatten

        time = nil
        issue.changes.each do |change|
          time = change.time if change.status? && trigger_statuses.include?(change.value) && change.artificial? == false
        end
        time
      end
    end

    issues_cutoff_times = []
    issues.each do |issue|
      cutoff_time = block.call(issue)
      issues_cutoff_times << [issue, cutoff_time] if cutoff_time
    end

    discard_changes_before_hook issues_cutoff_times

    issues_cutoff_times.each do |issue, cutoff_time|
      issue.discard_changes_before cutoff_time
    end
  end
end
