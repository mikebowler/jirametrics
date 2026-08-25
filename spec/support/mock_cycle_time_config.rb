# frozen_string_literal: true

# Stubs are matched by the issue's KEY, not by object identity, so every issue in a test needs its
# own key. Build four of them as load_issue 'SP-1' and you have one issue wearing four hats. That
# used to pass quietly against whichever stub came first; it now raises.
#
#   board.cycletime = MockCycleTimeConfig.new
#     .stub(issue1, started: '2021-01-02')
#     .stub(issue2, started: '2021-01-02', stopped: '2021-10-04')
#
# An issue with no stub at all reads as never started, which is a legitimate state and so cannot be
# distinguished from one you forgot.
class MockCycleTimeConfig < CycleTimeConfig
  def initialize stub_values: []
    super(possible_statuses: nil, label: nil, block: nil, settings: SpecHelpers.load_settings)

    raise 'Stubs must be arrays of [issue, start_time, stop_time] tuples' unless stub_values.is_a? Array

    # Built up through stub rather than held onto, so the caller's array is never rewritten under
    # them and the tuple form gets the same duplicate checking as the cascade.
    @stub_values = []
    stub_values.each { |line| stub_from_tuple line }
  end

  # Returns self so that calls cascade.
  def stub issue, started: nil, stopped: nil
    key = issue.is_a?(Issue) ? issue.key : issue
    assert_key_unused key
    @stub_values << [key, normalize_time(started), normalize_time(stopped)]
    self
  end

  def started_stopped_changes(issue)
    value = @stub_values.find { |issue_key, _start, _stop| issue_key == issue.key }
    return [nil, nil] unless value

    [to_change(value[1]), to_change(value[2])]
  end

  private

  def stub_from_tuple line
    key, started, stopped = line

    unless key.is_a?(Issue) || key =~ /^[A-Z]+-\d+$/
      raise 'Parameters to mock_cycletime_config must be an array of [issue, start_time, end_time] tuples'
    end

    stub key, started: started, stopped: stopped
  end

  def normalize_time value
    value.is_a?(String) ? SpecHelpers.to_time(value) : value
  end

  # Only the first stub for a key is reachable, so a second one always means the test is asserting
  # against something other than what it looks like.
  def assert_key_unused key
    return unless @stub_values.any? { |existing, _start, _stop| existing == key }

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
