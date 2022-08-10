# frozen_string_literal: true

module DiscardChangesBefore
  def discard_changes_before status_becomes: nil, &block
    if status_becomes
      status_becomes = [status_becomes] unless status_becomes.is_a? Array
      block = lambda do |issue|
        time = nil
        issue.changes.each do |change|
          time = change.time if change.status? && status_becomes.include?(change.value) && change.artificial? == false
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
      issue.changes.reject! { |change| change.status? && change.time <= cutoff_time && change.artificial? == false }
    end
  end
end
