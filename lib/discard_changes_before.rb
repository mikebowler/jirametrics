# frozen_string_literal: true

module DiscardChangesBefore
  def discard_changes_before status_becomes: nil, &block
    if status_becomes
      status_becomes = expand_backlog_statuses if status_becomes == :backlog
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

  def expand_backlog_statuses
    project_config = @file_config.project_config
    status_ids = project_config.all_boards[find_board_id].backlog_statuses
    # puts status_ids.inspect
    # puts project_config.possible_statuses.inspect
    puts project_config.file_prefix
    project_config.possible_statuses.select { |s| status_ids.include? s.id.to_i }.collect {|s| s.name}.tap {|a|puts a.inspect}
  end
end
