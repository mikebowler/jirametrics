# frozen_string_literal: true

# Builds the time-ordered stream of BlockedStalledChange entries for a single issue.
# Everything it needs is passed in explicitly (changes, settings, and a few resolved values)
# so it never reaches back through the issue's collaborators.
class BlockedStalledChangeStreamBuilder
  # Mutable state threaded through the change loop as we walk the issue's history. Each branch
  # only overwrites the fields it owns, so a flag/status/link value persists until the next change
  # of that kind replaces it.
  BlockingState = Struct.new(
    :flag, :flag_reason, :status, :is_blocked, :blocking_issue_keys, keyword_init: true
  )

  def initialize changes:, settings:, created:, key:, subtask_activity_times:, atlassian_document_format:
    @changes = changes
    @settings = settings
    @created = created
    @key = key
    @subtask_activity_times = subtask_activity_times
    @atlassian_document_format = atlassian_document_format
  end

  def build end_time:
    result = []
    state = BlockingState.new(flag: nil, flag_reason: nil, status: nil, is_blocked: false, blocking_issue_keys: [])
    previous_was_active = false # Must start as false so that the creation will insert an :active
    previous_change_time = @created

    # This mock change is to force the writing of one last entry at the end of the time range.
    # By doing this, we're able to eliminate a lot of duplicated code in charts.
    mock_change = ChangeItem.new time: end_time, artificial: true, raw: { 'field' => '' }, author_raw: nil

    (@changes + [mock_change]).each do |change|
      previous_was_active = false if check_for_stalled(
        change_time: change.time,
        previous_change_time: previous_change_time,
        stalled_threshold: @settings['stalled_threshold_days'],
        blocking_stalled_changes: result
      )

      update_blocking_state state, change

      new_change = new_blocked_stalled_change state, change.time

      # We don't want to dump two actives in a row as that would just be noise. Unless this is
      # the mock change, which we always want to dump
      result << new_change if record_change? new_change, previous_was_active, change, mock_change

      previous_was_active = new_change.active?
      previous_change_time = change.time
    end

    finalize_stalled_tail result
    result
  end

  def update_blocking_state state, change
    if change.flagged? && flagged_means_blocked?
      state.flag, state.flag_reason = flag_logic change
    elsif change.status?
      state.status, state.is_blocked = status_change change
    elsif change.link?
      apply_link_change change, state.blocking_issue_keys
    end
  end

  def flagged_means_blocked?
    !!@settings['flagged_means_blocked']
  end

  def new_blocked_stalled_change state, time
    BlockedStalledChange.new(
      flagged: state.flag,
      flag_reason: state.flag_reason,
      status: state.status,
      status_is_blocking: state.status.nil? || state.is_blocked,
      blocking_issue_keys: (state.blocking_issue_keys.empty? ? nil : state.blocking_issue_keys.dup),
      time: time
    )
  end

  def record_change? candidate, previous_was_active, change, mock_change
    !candidate.active? || !previous_was_active || change == mock_change
  end

  def status_change change
    if @settings['blocked_statuses'].find_by_id(change.value_id)
      [change.value, true]
    elsif @settings['stalled_statuses'].find_by_id(change.value_id)
      [change.value, false]
    else
      [nil, false]
    end
  end

  def apply_link_change change, blocking_issue_keys
    link_value = change.value || change.old_value
    # Example: "This issue is satisfied by ANON-30465"
    unless /^This (?<_>issue|work item) (?<link_text>.+) (?<issue_key>.+)$/ =~ link_value
      puts "Issue(#{@key}) Can't parse link text: #{link_value}"
      return
    end

    return unless @settings['blocked_link_text'].include? link_text

    if change.value
      blocking_issue_keys << issue_key
    else
      blocking_issue_keys.delete issue_key
    end
  end

  def flag_logic change
    flag = change.value
    flag = nil if change.value == ''
    [flag, flag ? flag_reason_from_comment(change) : nil]
  end

  def flag_reason_from_comment change
    comment_change = comment_near change.time
    flag_reason = comment_change && @atlassian_document_format.to_text(comment_change.value)
    # Newer Jira instances may add this extra text but older instances did not. Strip it out if found.
    flag_reason = flag_reason&.sub(/\A:flag_on: Flag added\s*/m, '')&.strip
    flag_reason = nil if flag_reason && flag_reason.empty?
    flag_reason
  end

  def comment_near flag_time
    # When the user is adding a comment to explain why a flag was set, the flag is set immediately
    # and the comment is inserted after the user hits enter, which means that there is some time
    # gap. If a comment happened shortly after the flag was set, we assume they're linked. This
    # won't always be true and so there will be false positives, but it's a reasonable assumption.
    max_seconds_between_flag_and_comment = 30
    @changes.find do |c|
      c.comment? && c.time >= flag_time && (c.time - flag_time) <= max_seconds_between_flag_and_comment
    end
  end

  def finalize_stalled_tail result
    return unless result.size >= 2

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

  def check_for_stalled change_time:, previous_change_time:, stalled_threshold:, blocking_stalled_changes:
    stalled_threshold_seconds = stalled_threshold * 60 * 60 * 24

    # The most common case will be nothing to split so quick escape.
    return false if (change_time - previous_change_time).to_i < stalled_threshold_seconds

    # If the last identified change was blocked then it doesn't matter now long we've waited, we're still blocked.
    return false if blocking_stalled_changes[-1]&.blocked?

    ranges = split_range_by_subtask_activity previous_change_time..change_time
    insert_stalled_changes ranges, stalled_threshold_seconds, blocking_stalled_changes
  end

  def split_range_by_subtask_activity initial_range
    list = [initial_range]
    @subtask_activity_times.each do |time|
      matching_range = list.find { |range| time.between?(range.begin, range.end) }
      next unless matching_range

      list.delete matching_range
      list << (matching_range.begin..time)
      list << (time..matching_range.end)
    end
    list
  end

  def insert_stalled_changes ranges, stalled_threshold_seconds, blocking_stalled_changes
    inserted_stalled = false
    ranges.sort_by(&:begin).each do |range|
      seconds = (range.end - range.begin).to_i
      next if seconds < stalled_threshold_seconds

      an_hour_later = range.begin + (60 * 60)
      blocking_stalled_changes << BlockedStalledChange.new(stalled_days: seconds / (24 * 60 * 60), time: an_hour_later)
      inserted_stalled = true
    end
    inserted_stalled
  end
end
