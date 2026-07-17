# frozen_string_literal: true

# Builds the time-ordered stream of BlockedStalledChange entries for a single issue.
# Everything it needs is passed in explicitly (changes, settings, and a few resolved values)
# so it never reaches back through the issue's collaborators.
class BlockedStalledChangeStreamBuilder
  def initialize changes:, settings:, created:, key:, subtask_activity_times:, atlassian_document_format:
    @changes = changes
    @settings = settings
    @created = created
    @key = key
    @subtask_activity_times = subtask_activity_times
    @atlassian_document_format = atlassian_document_format
  end

  def build end_time:
    blocked_statuses = @settings['blocked_statuses']
    stalled_statuses = @settings['stalled_statuses']

    blocked_link_texts = @settings['blocked_link_text']
    stalled_threshold = @settings['stalled_threshold_days']
    flagged_means_blocked = !!@settings['flagged_means_blocked'] # rubocop:disable Style/DoubleNegation

    blocking_issue_keys = []

    result = []
    previous_was_active = false # Must start as false so that the creation will insert an :active
    previous_change_time = @created

    blocking_status = nil
    blocking_is_blocked = false
    flag = nil
    flag_reason = nil

    # This mock change is to force the writing of one last entry at the end of the time range.
    # By doing this, we're able to eliminate a lot of duplicated code in charts.
    mock_change = ChangeItem.new time: end_time, artificial: true, raw: { 'field' => '' }, author_raw: nil

    (@changes + [mock_change]).each do |change|
      previous_was_active = false if check_for_stalled(
        change_time: change.time,
        previous_change_time: previous_change_time,
        stalled_threshold: stalled_threshold,
        blocking_stalled_changes: result
      )

      if change.flagged? && flagged_means_blocked
        flag, flag_reason = flag_logic change
      elsif change.status?
        blocking_status = nil
        blocking_is_blocked = false
        if blocked_statuses.find_by_id(change.value_id)
          blocking_status = change.value
          blocking_is_blocked = true
        elsif stalled_statuses.find_by_id(change.value_id)
          blocking_status = change.value
        end
      elsif change.link?
        # Example: "This issue is satisfied by ANON-30465"
        unless /^This (?<_>issue|work item) (?<link_text>.+) (?<issue_key>.+)$/ =~ (change.value || change.old_value)
          puts "Issue(#{@key}) Can't parse link text: #{change.value || change.old_value}"
          next
        end

        if blocked_link_texts.include? link_text
          if change.value
            blocking_issue_keys << issue_key
          else
            blocking_issue_keys.delete issue_key
          end
        end
      end

      new_change = BlockedStalledChange.new(
        flagged: flag,
        flag_reason: flag_reason,
        status: blocking_status,
        status_is_blocking: blocking_status.nil? || blocking_is_blocked,
        blocking_issue_keys: (blocking_issue_keys.empty? ? nil : blocking_issue_keys.dup),
        time: change.time
      )

      # We don't want to dump two actives in a row as that would just be noise. Unless this is
      # the mock change, which we always want to dump
      result << new_change if !new_change.active? || !previous_was_active || change == mock_change

      previous_was_active = new_change.active?
      previous_change_time = change.time
    end

    if result.size >= 2
      # The existence of the mock entry will mess with the stalled count as it will wake everything
      # back up. This hack will clean up appropriately.
      hack = result.pop
      result << BlockedStalledChange.new(
        flagged: hack.flag,
        flag_reason: hack.flag_reason,
        status: hack.status,
        status_is_blocking: hack.status_is_blocking,
        blocking_issue_keys: hack.blocking_issue_keys,
        time: hack.time,
        stalled_days: result[-1].stalled_days
      )
    end

    result
  end

  def flag_logic change
    flag = change.value
    flag = nil if change.value == ''
    if flag
      # When the user is adding a comment to explain why a flag was set, the flag is set immediately
      # and the comment is inserted after the user hits enter, which means that there is some time
      # gap. If a comment happened shortly after the flag was set, we assume they're linked. This
      # won't always be true and so there will be false positives, but it's a reasonable assumption.
      max_seconds_between_flag_and_comment = 30
      comment_change = @changes.find do |c|
        c.comment? && c.time >= change.time && (c.time - change.time) <= max_seconds_between_flag_and_comment
      end
      flag_reason = comment_change && @atlassian_document_format.to_text(comment_change.value)
      # Newer Jira instances may add this extra text but older instances did not. Strip it out if found.
      flag_reason = flag_reason&.sub(/\A:flag_on: Flag added\s*/m, '')&.strip
      flag_reason = nil if flag_reason && flag_reason.empty?
    else
      flag_reason = nil
    end
    [flag, flag_reason]
  end

  def check_for_stalled change_time:, previous_change_time:, stalled_threshold:, blocking_stalled_changes:
    stalled_threshold_seconds = stalled_threshold * 60 * 60 * 24

    # The most common case will be nothing to split so quick escape.
    return false if (change_time - previous_change_time).to_i < stalled_threshold_seconds

    # If the last identified change was blocked then it doesn't matter now long we've waited, we're still blocked.
    return false if blocking_stalled_changes[-1]&.blocked?

    list = [previous_change_time..change_time]
    @subtask_activity_times.each do |time|
      matching_range = list.find { |range| time.between?(range.begin, range.end) }
      next unless matching_range

      list.delete matching_range
      list << ((matching_range.begin)..time)
      list << (time..(matching_range.end))
    end

    inserted_stalled = false

    list.sort_by(&:begin).each do |range|
      seconds = (range.end - range.begin).to_i
      next if seconds < stalled_threshold_seconds

      an_hour_later = range.begin + (60 * 60)
      blocking_stalled_changes << BlockedStalledChange.new(stalled_days: seconds / (24 * 60 * 60), time: an_hour_later)
      inserted_stalled = true
    end
    inserted_stalled
  end
end
