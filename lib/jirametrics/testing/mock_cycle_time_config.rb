# frozen_string_literal: true

# Stubs are matched by the issue's KEY, not by object identity, so every issue in a test needs its
# own key. Building two issues with the same key and stubbing both raises.
#
#   board.cycletime = MockCycleTimeConfig.new
#     .stub(issue1, started: '2021-01-02')
#     .stub(issue2, started: '2021-01-02', stopped: '2021-10-04')
#
# An issue with no stub at all reads as never started, which is a legitimate state and so cannot be
# distinguished from one you forgot.
class MockCycleTimeConfig < CycleTimeConfig
  def initialize
    super(possible_statuses: nil, label: nil, block: nil, settings: self.class.default_settings)
    @stubs = []
  end

  # The same file ProjectConfig reads, resolved from this file's own location so that it works from
  # wherever the caller happens to be rather than only from a checkout of this repo.
  def self.default_settings
    settings_file = File.expand_path '../settings.json', __dir__
    JSON.parse(File.read(settings_file, encoding: 'UTF-8')).tap do |settings|
      # A cached cycle time would outlive the stub that produced it, so a second stub for the same
      # issue would appear to have no effect.
      settings['cache_cycletime_calculations'] = false
    end
  end

  # Returns self so that calls cascade.
  def stub issue, started: nil, stopped: nil
    key = issue.is_a?(Issue) ? issue.key : issue
    assert_key_unused key
    @stubs << [key, normalize_time(started), normalize_time(stopped)]
    self
  end

  def started_stopped_changes(issue)
    value = @stubs.find { |issue_key, _start, _stop| issue_key == issue.key }
    return [nil, nil] unless value

    [to_change(value[1]), to_change(value[2])]
  end

  private

  def normalize_time value
    value.is_a?(String) ? JiraMetrics::Testing.to_time(value) : value
  end

  # Only the first stub for a key is reachable, so a second one always means the test is asserting
  # against something other than what it looks like.
  def assert_key_unused key
    return unless @stubs.any? { |existing, _start, _stop| existing == key }

    raise "More than one stub for #{key}. Stubs are matched by issue key, so only the first would " \
      'ever be used. Give each issue its own key.'
  end

  def to_change change
    case change
    when nil
      nil
    when ChangeItem
      change
    else
      MockChangeItem.new(field: 'status', value: 'fake', value_id: 1_000_001, time: change&.to_time).to_change_item
    end
  end
end
