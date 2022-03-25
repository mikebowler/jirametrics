# frozen_string_literal: true

module DiscardChangesBefore
  def discard_changes_before status_becomes: nil, &block
    if status_becomes
      block = lambda do |issue|
        time = nil
        issue.changes.each do |change|
          time = change.time if change.status? && change.value == status_becomes && change.artificial? == false
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
      issue.changes.reject! { |change| change.status? && change.time < cutoff_time }
    end
  end
end
